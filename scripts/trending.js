// Live "what's popular" from Spotify data: charts playlists if readable, else year-filtered search ranked by popularity.
import { spotify, api } from "../src/spotify.js";
import { readFileSync } from "node:fs";
import { announceBudget, isBudgetError } from "./lib.js";
const lib = JSON.parse(readFileSync(process.argv[2], "utf8"));
const known = new Set([...lib.liked, ...Object.values(lib.playlists).flatMap(p => p.tracks)].map(t => t.id));
const out = new Map(); const add = (t, src) => { if (t?.id && !known.has(t.id) && !out.has(t.id)) out.set(t.id, { ...t, src }); };

// 1. Charts (editorial) — may be 403 for new apps
for (const [name, id] of [["Top 50 Israel", "37i9dQZEVXbJ6IpvItkve3"], ["Top 50 Global", "37i9dQZEVXbMDoHDwVN2tF"], ["Viral 50 Israel", "37i9dQZEVXbNGlbFNNXxgC"], ["Hot Hits Israel", "37i9dQZF1DWSYF6geMtQMW"]]) {
  try { const p = await spotify.getPlaylist(id); p.tracks.forEach(t => add(t, name)); console.log(`${name}: ${p.tracks.length} ✓`); }
  catch (e) { console.log(`${name}: blocked (${e.message.slice(0, 60)})`); }
}

announceBudget(65);
// 2. Search, year-filtered, ranked by live popularity
const Q = [
  // Israel
  "year:2025-2026 tag:new", "עברית year:2025-2026", "שיר year:2026", "אהבה year:2025-2026", "לילה year:2025-2026", "תל אביב year:2025-2026", "ישראל year:2025-2026", "מזרחית year:2025-2026", "ים year:2025-2026", "לב year:2025-2026",
  // World
  "year:2026", "year:2025", "genre:pop year:2026", "genre:hip-hop year:2026", "genre:dance year:2026", "genre:rock year:2025-2026", "genre:indie year:2025-2026", "genre:afrobeats year:2025-2026", "genre:latin year:2026", "genre:k-pop year:2026", "genre:electronic year:2026", "genre:metal year:2025-2026", "love year:2026", "night year:2026", "summer year:2026",
];
for (const q of Q) { try { (await spotify.search(q, "track", 50)).forEach(t => add(t, "search:" + q)); } catch (e) { if (isBudgetError(e)) { console.log("stopping:", e.message); break; } console.log("search failed:", q); } }

// 3. New releases from YOUR top artists
const tops = [...new Set([...lib.topArtists.short_term, ...lib.topArtists.medium_term, ...lib.topArtists.long_term].map(a => a.name))].slice(0, 40);
for (const a of tops) { try { (await spotify.search(`artist:"${a}" year:2025-2026`, "track", 10)).forEach(t => add(t, "your artist: " + a)); } catch (e) { if (isBudgetError(e)) break; } }

// Rank: popularity desc; split Israel vs world by Hebrew chars / Israeli source
const all = [...out.values()].filter(t => (t.popularity ?? 0) >= 40).sort((a, b) => b.popularity - a.popularity);
const isIL = t => /[֐-׿]/.test(t.name + t.artists) || /Israel|your artist/.test(t.src) && /[֐-׿]/.test(t.name + t.artists);
const il = all.filter(isIL).slice(0, 60), world = all.filter(t => !isIL(t)).slice(0, 100), yours = all.filter(t => t.src.startsWith("your artist")).slice(0, 40);
const ids = [...new Set([...il, ...world, ...yours].map(t => t.id))];
const ex = (await spotify.listPlaylists()).find(p => p.name === "📈 Trending");
const pl = ex ?? await spotify.createPlaylist({ name: "📈 Trending", description: "Live from Spotify popularity · Israel + world + new releases from your artists" });
console.log(await spotify.addTracks(pl.id, ids));
console.log("\nTOP ISRAEL:", il.slice(0, 25).map(t => `${t.name} – ${t.artists} (${t.popularity})`).join(" | "));
console.log("\nTOP WORLD:", world.slice(0, 25).map(t => `${t.name} – ${t.artists} (${t.popularity})`).join(" | "));
console.log("\nYOUR ARTISTS, NEW:", yours.slice(0, 25).map(t => `${t.name} – ${t.artists} (${t.release})`).join(" | "));
