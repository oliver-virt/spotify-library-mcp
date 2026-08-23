import { loadEnv } from "./env.js";
import { budget } from "./budget.js";

loadEnv();

const ACCOUNTS = process.env.SPOTIFY_ACCOUNTS_URL ?? "https://accounts.spotify.com";
const API = process.env.SPOTIFY_API_URL ?? "https://api.spotify.com/v1";

let accessToken = null;
let expiresAt = 0;

// Pacing: a burst of ~500 calls got this client silently dropped at TLS level for ~10 minutes (not a 429).
// Keep a minimum gap between requests; 429s are still honoured via Retry-After below.
const MIN_GAP_MS = Number(process.env.SPOTIFY_MIN_GAP_MS ?? 150);
let lastCall = 0;
async function pace() {
  const wait = lastCall + MIN_GAP_MS - Date.now();
  if (wait > 0) await new Promise((r) => setTimeout(r, wait));
  lastCall = Date.now();
}

// Endpoints Spotify removed for apps created after Nov 2024 / renamed in 2026. Fail fast with a useful message.
const GONE = [
  [/^\/audio-features/, "audio-features was removed for new apps (Nov 2024). No energy/tempo data is available."],
  [/^\/recommendations/, "recommendations was removed for new apps (Nov 2024). Use search + your own knowledge."],
  [/^\/artists\/[^/]+\/related-artists/, "related-artists was removed for new apps."],
  [/^\/(tracks|artists|albums)$/, "batch GET /tracks|/artists|/albums (?ids=) returns 403 for new apps. Use the single-item endpoint. Note: artist objects no longer include genres."],
  [/^\/playlists\/[^/]+\/tracks/, "renamed: use /playlists/{id}/items (2026). Items are under `item`, not `track`."],
  [/^\/users\/[^/]+\/playlists/, "deprecated: create playlists with POST /me/playlists."],
  [/^\/me\/tracks$/, "PUT/DELETE /me/tracks is deprecated: use /me/library?uris=... (max 20 URIs per call)."],
];

function required(name) {
  const v = process.env[name];
  if (!v) throw new Error(`Missing ${name}. Copy .env.example to .env and run \`npm run auth\`.`);
  return v;
}

export async function refreshAccessToken() {
  const clientId = required("SPOTIFY_CLIENT_ID");
  const refreshToken = required("SPOTIFY_REFRESH_TOKEN");
  const body = new URLSearchParams({ grant_type: "refresh_token", refresh_token: refreshToken, client_id: clientId });
  const headers = { "Content-Type": "application/x-www-form-urlencoded" };
  // Secret is optional: PKCE apps refresh with client_id only.
  if (process.env.SPOTIFY_CLIENT_SECRET) {
    headers.Authorization = "Basic " + Buffer.from(`${clientId}:${process.env.SPOTIFY_CLIENT_SECRET}`).toString("base64");
  }
  const res = await fetch(`${ACCOUNTS}/api/token`, { method: "POST", headers, body });
  if (!res.ok) throw new Error(`Token refresh failed (${res.status}): ${await res.text()}`);
  const json = await res.json();
  accessToken = json.access_token;
  expiresAt = Date.now() + (json.expires_in - 60) * 1000;
  // Spotify may rotate the refresh token under PKCE; keep using the newest in-process.
  if (json.refresh_token) process.env.SPOTIFY_REFRESH_TOKEN = json.refresh_token;
  return accessToken;
}

async function token() {
  if (accessToken && Date.now() < expiresAt) return accessToken;
  return refreshAccessToken();
}

export async function api(method, path, { query, body, retries = 3 } = {}) {
  const url = new URL(path.startsWith("http") ? path : API + path);
  const rel = url.pathname.replace(/^\/v1/, "");
  const readingLikes = method === "GET" && rel === "/me/tracks"; // GET /me/tracks still works; only PUT/DELETE moved
  if (!readingLikes) for (const [re, msg] of GONE) if (re.test(rel)) throw new Error(`Spotify API limit: ${msg}`);
  await pace();
  if (query) for (const [k, v] of Object.entries(query)) if (v !== undefined && v !== null) url.searchParams.set(k, String(v));
  let res;
  for (let attempt = 0; ; attempt++) {
    try {
      res = await fetch(url, {
        method,
        headers: { Authorization: `Bearer ${await token()}`, ...(body ? { "Content-Type": "application/json" } : {}) },
        body: body ? JSON.stringify(body) : undefined,
        signal: AbortSignal.timeout(20000),
      });
      break;
    } catch (e) {
      if (attempt >= 6) throw e;
      const wait = Math.min(30000, 2000 * 2 ** attempt);
      process.stderr.write(`network error (${e.cause?.code ?? e.name}), retry ${attempt + 1} in ${wait / 1000}s\n`);
      await new Promise((r) => setTimeout(r, wait));
    }
  }
  if (res.status === 429) {
    const secs = Number(res.headers.get("retry-after")) || 1;
    // Spotify hands out multi-hour bans on /search (e.g. 75469s after ~1000 searches/day). Never sleep through those.
    if (secs > 60 && url.pathname.endsWith("/search")) budget.ban(secs);
    if (secs > 60 || retries === 0) throw new Error(`Spotify rate limit on ${url.pathname}: retry after ${secs}s (~${(secs / 3600).toFixed(1)}h). Per-app limit — a different Spotify app (client id) has its own quota.`);
    const wait = secs * 1000;
    await new Promise((r) => setTimeout(r, wait));
    return api(method, path, { query, body, retries: retries - 1 });
  }
  if (res.status === 401 && retries > 0) {
    accessToken = null;
    return api(method, path, { query, body, retries: 0 });
  }
  if (!res.ok) throw new Error(`Spotify ${method} ${url.pathname} → ${res.status}: ${await res.text()}`);
  if (res.status === 204) return null;
  const text = await res.text();
  return text ? JSON.parse(text) : null;
}

// Walk a paginated endpoint to completion.
export async function paginate(path, query = {}, limit = 50) {
  const items = [];
  let next = null;
  let page = await api("GET", path, { query: { ...query, limit } });
  for (;;) {
    items.push(...page.items);
    next = page.next;
    if (!next) break;
    page = await api("GET", next);
  }
  return items;
}

function chunk(arr, n) {
  const out = [];
  for (let i = 0; i < arr.length; i += n) out.push(arr.slice(i, i + n));
  return out;
}

const toUri = (id) => (id.startsWith("spotify:") ? id : `spotify:track:${id}`);
const slimTrack = (t) =>
  t && {
    id: t.id,
    uri: t.uri,
    name: t.name,
    artists: (t.artists ?? []).map((a) => a.name).join(", "),
    album: t.album?.name,
    duration_ms: t.duration_ms,
    popularity: t.popularity,
    release: t.album?.release_date,
  };

export const searchBudget = () => budget.status();

export const spotify = {
  me: () => api("GET", "/me"),

  async listPlaylists() {
    const me = await this.me();
    const items = await paginate("/me/playlists");
    return items.map((p) => ({
      id: p.id,
      name: p.name,
      description: p.description,
      tracks: p.items?.total ?? p.tracks?.total,
      public: p.public,
      collaborative: p.collaborative,
      owner: p.owner?.display_name ?? p.owner?.id,
      mine: p.owner?.id === me.id,
      url: p.external_urls?.spotify,
    }));
  },

  async getPlaylist(id) {
    const p = await api("GET", `/playlists/${id}`, { query: { fields: "id,name,description,public,owner(id,display_name),items.total,snapshot_id" } });
    const items = await paginate(`/playlists/${id}/items`, { fields: "next,items(added_at,item(id,uri,name,duration_ms,artists(name),album(name)))" }, 100);
    return { id: p.id, name: p.name, description: p.description, public: p.public, owner: p.owner, snapshot_id: p.snapshot_id, total: p.items?.total, tracks: items.map((i) => ({ added_at: i.added_at, ...slimTrack(i.item ?? i.track) })).filter((t) => t.id) };
  },

  async createPlaylist({ name, description = "", isPublic = false }) {
    return api("POST", "/me/playlists", { body: { name, description, public: isPublic } });
  },

  updatePlaylist(id, details) {
    const body = {};
    if (details.name !== undefined) body.name = details.name;
    if (details.description !== undefined) body.description = details.description;
    if (details.isPublic !== undefined) body.public = details.isPublic;
    return api("PUT", `/playlists/${id}`, { body });
  },

  async addTracks(id, trackIds, { dedupe = true } = {}) {
    let uris = trackIds.map(toUri);
    if (dedupe) {
      const existing = new Set((await this.getPlaylist(id)).tracks.map((t) => t.uri));
      uris = [...new Set(uris)].filter((u) => !existing.has(u));
    }
    let snapshot = null;
    for (const c of chunk(uris, 100)) snapshot = (await api("POST", `/playlists/${id}/items`, { body: { uris: c } }))?.snapshot_id ?? snapshot;
    return { added: uris.length, snapshot_id: snapshot };
  },

  async removeTracks(id, trackIds) {
    const uris = trackIds.map(toUri);
    let snapshot = null;
    for (const c of chunk(uris, 100))
      snapshot = (await api("DELETE", `/playlists/${id}/items`, { body: { items: c.map((uri) => ({ uri })) } }))?.snapshot_id ?? snapshot;
    return { removed: uris.length, snapshot_id: snapshot };
  },

  // Spotify has no delete: "unfollowing" your own playlist removes it from your library.
  deletePlaylist: (id) => api("DELETE", `/playlists/${id}/followers`),

  async mergePlaylists({ sourceIds, targetId, newName, deleteSources = false }) {
    const collected = [];
    for (const sid of sourceIds) collected.push(...(await this.getPlaylist(sid)).tracks.map((t) => t.uri));
    let target = targetId;
    if (!target) target = (await this.createPlaylist({ name: newName ?? "Merged" })).id;
    const result = await this.addTracks(target, collected);
    if (deleteSources) for (const sid of sourceIds) if (sid !== target) await this.deletePlaylist(sid);
    return { targetId: target, unique_tracks_seen: new Set(collected).size, ...result };
  },

  async saveTracks(trackIds) {
    const uris = trackIds.map(toUri);
    for (const c of chunk(uris, 20)) await api("PUT", "/me/library", { query: { uris: c.join(",") } });
    return { saved: uris.length };
  },

  async savedTracks() {
    const items = await paginate("/me/tracks", {}, 50);
    return items.map((i) => ({ added_at: i.added_at, ...slimTrack(i.track) }));
  },

  async search(q, type = "track", limit = 10) {
    const key = `${type}|${limit}|${q}`;
    const hit = budget.cacheGet(key);
    if (hit) return hit;
    budget.check();
    const r = await api("GET", "/search", { query: { q, type, limit } });
    budget.spend();
    const out = (r[`${type}s`]?.items ?? []).map((x) => (type === "track" ? slimTrack(x) : { id: x.id, uri: x.uri, name: x.name, type: x.type }));
    budget.cacheSet(key, out);
    return out;
  },

  // Search that verifies the artist name appears on the result — plain search happily returns karaoke versions and covers.
  async findTrack(track, artist) {
    const norm = (x) => x.toLowerCase().replace(/[^\p{L}\p{N}]/gu, "");
    const res = await this.search(`${track} ${artist}`, "track", 10);
    return res.find((r) => norm(r.artists).includes(norm(artist)) && !/karaoke|tribute|cover|instrumental/i.test(r.artists + " " + r.album)) ?? null;
  },

  async removeSavedTracks(trackIds) {
    const uris = trackIds.map(toUri);
    for (const c of chunk(uris, 20)) await api("DELETE", "/me/library", { query: { uris: c.join(",") } });
    return { removed: uris.length };
  },

  topTracks: (range = "medium_term", limit = 50) =>
    api("GET", "/me/top/tracks", { query: { time_range: range, limit } }).then((r) => r.items.map(slimTrack)),
  topArtists: (range = "medium_term", limit = 50) =>
    api("GET", "/me/top/artists", { query: { time_range: range, limit } }).then((r) => r.items.map((a) => ({ id: a.id, name: a.name, genres: a.genres }))),
  recentlyPlayed: (limit = 50) =>
    api("GET", "/me/player/recently-played", { query: { limit } }).then((r) => r.items.map((i) => ({ played_at: i.played_at, ...slimTrack(i.track) }))),
};
