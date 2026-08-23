// Server-side library analysis. Computation happens here, not in the LLM: tools return compact summaries.
import { readFileSync, writeFileSync, existsSync, mkdirSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { spotify } from "./spotify.js";
import { ROOT } from "./env.js";

const SNAP_DIR = process.env.SPOTIFY_SNAPSHOT_DIR ?? join(ROOT, "backups");
let index = null, indexAt = 0;
const TTL = Number(process.env.SPOTIFY_INDEX_TTL_MS ?? 10 * 60 * 1000);

export async function libraryIndex({ refresh = false } = {}) {
  if (index && !refresh && Date.now() - indexAt < TTL) return index;
  const playlists = {};
  for (const p of (await spotify.listPlaylists()).filter((p) => p.mine)) playlists[p.id] = await spotify.getPlaylist(p.id);
  const liked = await spotify.savedTracks();
  index = { playlists, liked, fetchedAt: new Date().toISOString() };
  indexAt = Date.now();
  return index;
}

const year = (t) => Number((t.release ?? "").slice(0, 4)) || null;
const decade = (t) => { const y = year(t); return y ? `${Math.floor(y / 10) * 10}s` : "unknown"; };
const primary = (t) => t.artists.split(", ")[0];
const fuzzyKey = (t) => `${primary(t).toLowerCase()}|${t.name.toLowerCase().replace(/\s*[-(\[].*(remaster|version|edit|live|mix|feat).*$/i, "").trim()}`;
const top = (counts, n = 10) => Object.entries(counts).sort((a, b) => b[1] - a[1]).slice(0, n).map(([k, v]) => ({ name: k, count: v }));
const fmt = (ms) => { const m = Math.round(ms / 60000); return m >= 60 ? `${Math.floor(m / 60)}h ${m % 60}m` : `${m}m`; };

export function summarizeTracks(tracks) {
  const artists = {}, decades = {}, added = {};
  let ms = 0;
  for (const t of tracks) {
    artists[primary(t)] = (artists[primary(t)] || 0) + 1;
    decades[decade(t)] = (decades[decade(t)] || 0) + 1;
    if (t.added_at) { const y = t.added_at.slice(0, 4); added[y] = (added[y] || 0) + 1; }
    ms += t.duration_ms ?? 0;
  }
  const seen = new Map(), dupes = [];
  for (const t of tracks) { const k = fuzzyKey(t); if (seen.has(k)) dupes.push({ name: t.name, artists: t.artists, ids: [seen.get(k), t.id] }); else seen.set(k, t.id); }
  const hebrew = tracks.filter((t) => /[֐-׿]/.test(t.name + t.artists)).length;
  return {
    tracks: tracks.length, runtime: fmt(ms), distinct_artists: Object.keys(artists).length,
    top_artists: top(artists), decades: Object.fromEntries(Object.entries(decades).sort()), added_by_year: added,
    hebrew_share: tracks.length ? Math.round((100 * hebrew) / tracks.length) + "%" : "0%",
    duplicates: dupes.length, duplicate_examples: dupes.slice(0, 10),
    most_overrepresented: top(artists, 1)[0] && Math.round((100 * top(artists, 1)[0].count) / tracks.length) + "% " + top(artists, 1)[0].name,
  };
}

export async function summarizePlaylist(id) {
  const p = await spotify.getPlaylist(id);
  return { id: p.id, name: p.name, ...summarizeTracks(p.tracks) };
}

export async function summarizeLibrary() {
  const { playlists, liked } = await libraryIndex();
  const inPl = new Set(Object.values(playlists).flatMap((p) => p.tracks.map((t) => t.id)));
  const orphans = liked.filter((t) => !inPl.has(t.id));
  const all = new Map(); for (const t of [...liked, ...Object.values(playlists).flatMap((p) => p.tracks)]) all.set(t.id, t);
  const perPl = Object.values(playlists).map((p) => ({ id: p.id, name: p.name, tracks: p.tracks.length, last_added: p.tracks.map((t) => t.added_at).sort().pop()?.slice(0, 10) ?? null }));
  const overlaps = [];
  const ids = Object.keys(playlists);
  for (let i = 0; i < ids.length; i++) for (let j = i + 1; j < ids.length; j++) {
    const a = new Set(playlists[ids[i]].tracks.map((t) => t.id)); const n = playlists[ids[j]].tracks.filter((t) => a.has(t.id)).length;
    if (n >= 3) overlaps.push({ a: playlists[ids[i]].name, b: playlists[ids[j]].name, shared: n });
  }
  return {
    playlists: perPl.length, liked: liked.length, unique_tracks: all.size,
    liked_in_no_playlist: orphans.length, orphan_examples: orphans.slice(0, 10).map((t) => `${t.name} – ${t.artists}`),
    stale_playlists: perPl.filter((p) => p.last_added && p.last_added < new Date(Date.now() - 2 * 365 * 864e5).toISOString().slice(0, 10)).map((p) => p.name),
    empty_playlists: perPl.filter((p) => !p.tracks).map((p) => p.name),
    overlaps: overlaps.sort((a, b) => b.shared - a.shared).slice(0, 15),
    per_playlist: perPl, liked_summary: summarizeTracks(liked),
  };
}

export async function findInPlaylists(query) {
  const { playlists, liked } = await libraryIndex();
  const q = query.toLowerCase();
  const hit = (t) => `${t.name} ${t.artists}`.toLowerCase().includes(q) || t.id === query || t.uri === query;
  const out = [];
  for (const p of Object.values(playlists)) for (const t of p.tracks) if (hit(t)) out.push({ playlist: p.name, playlist_id: p.id, track: `${t.name} – ${t.artists}`, id: t.id, added_at: t.added_at });
  return { matches: out, liked: liked.filter(hit).map((t) => `${t.name} – ${t.artists}`) };
}

export async function dedupeReport() {
  const { playlists } = await libraryIndex();
  const within = {}; let total = 0;
  for (const p of Object.values(playlists)) { const d = summarizeTracks(p.tracks); if (d.duplicates) { within[p.name] = d.duplicate_examples; total += d.duplicates; } }
  return { duplicates_within_playlists: total, details: within, note: "Use remove_tracks with the second id of each pair to fix. Cross-playlist overlap is in summarize_library.overlaps." };
}

export async function playlistDiff(aId, bId) {
  const [a, b] = await Promise.all([spotify.getPlaylist(aId), spotify.getPlaylist(bId)]);
  const ids = (p) => new Set(p.tracks.map((t) => t.id));
  const A = ids(a), B = ids(b);
  const only = (p, other) => p.tracks.filter((t) => !other.has(t.id)).map((t) => ({ id: t.id, track: `${t.name} – ${t.artists}` }));
  return { a: a.name, b: b.name, shared: a.tracks.filter((t) => B.has(t.id)).length, only_in_a: only(a, B), only_in_b: only(b, A) };
}

// Snapshots: whole-library JSON on disk; "what changed since" diffs against the latest (or a named) snapshot.
export async function snapshotLibrary(label = "") {
  const { playlists, liked } = await libraryIndex({ refresh: true });
  mkdirSync(SNAP_DIR, { recursive: true });
  const name = `snapshot-${new Date().toISOString().replace(/[:.]/g, "-")}${label ? "-" + label : ""}.json`;
  writeFileSync(join(SNAP_DIR, name), JSON.stringify({ playlists, liked }));
  return { file: name, playlists: Object.keys(playlists).length, liked: liked.length };
}
export function listSnapshots() { return existsSync(SNAP_DIR) ? readdirSync(SNAP_DIR).filter((f) => f.endsWith(".json")).sort() : []; }
export async function changesSince(file) {
  const files = listSnapshots(); const pick = file ?? files.at(-1);
  if (!pick) return { error: "no snapshots yet; call snapshot_library first" };
  const old = JSON.parse(readFileSync(join(SNAP_DIR, pick), "utf8"));
  const cur = await libraryIndex({ refresh: true });
  const oldPl = old.playlists ?? {}, out = { since: pick, playlists: [] };
  const names = new Map(Object.values(oldPl).map((p) => [p.id, p.name]));
  for (const id of new Set([...Object.keys(oldPl), ...Object.keys(cur.playlists)])) {
    const o = oldPl[id], c = cur.playlists[id];
    if (!o) { out.playlists.push({ name: c.name, status: "created", tracks: c.tracks.length }); continue; }
    if (!c) { out.playlists.push({ name: names.get(id), status: "deleted", tracks: o.tracks.length }); continue; }
    const O = new Set(o.tracks.map((t) => t.id)), C = new Set(c.tracks.map((t) => t.id));
    const added = c.tracks.filter((t) => !O.has(t.id)), removed = o.tracks.filter((t) => !C.has(t.id));
    if (added.length || removed.length || o.name !== c.name) out.playlists.push({ name: c.name, renamed_from: o.name !== c.name ? o.name : undefined, added: added.map((t) => `${t.name} – ${t.artists}`), removed: removed.map((t) => `${t.name} – ${t.artists}`) });
  }
  const L = new Set((old.liked ?? []).map((t) => t.id)), Lc = new Set(cur.liked.map((t) => t.id));
  out.liked = { added: cur.liked.filter((t) => !L.has(t.id)).map((t) => `${t.name} – ${t.artists}`), removed: (old.liked ?? []).filter((t) => !Lc.has(t.id)).map((t) => `${t.name} – ${t.artists}`) };
  return out;
}

// Rediscover: liked long ago, absent from every top-tracks range and from recent plays.
export async function rediscover({ minYearsAgo = 3, limit = 50 } = {}) {
  const { liked } = await libraryIndex();
  const cutoff = new Date(Date.now() - minYearsAgo * 365 * 864e5).toISOString();
  const hot = new Set();
  for (const r of ["short_term", "medium_term", "long_term"]) for (const t of await spotify.topTracks(r, 50)) hot.add(t.id);
  try { for (const t of await spotify.recentlyPlayed(50)) hot.add(t.id); } catch {}
  const old = liked.filter((t) => t.added_at < cutoff && !hot.has(t.id));
  // spread across years and artists so it's not 50 songs by one band
  const seen = {}, out = [];
  for (const t of old.sort((a, b) => a.added_at.localeCompare(b.added_at))) { const a = primary(t); if ((seen[a] || 0) >= 3) continue; seen[a] = (seen[a] || 0) + 1; out.push(t); }
  return { candidates: old.length, tracks: out.slice(0, limit).map((t) => ({ id: t.id, track: `${t.name} – ${t.artists}`, liked_on: t.added_at.slice(0, 10) })) };
}
