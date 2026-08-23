// Snapshot your library (owned playlists, liked songs, top tracks/artists, recent) to a JSON file used by the build scripts.
import { writeFileSync } from "node:fs";
import { spotify } from "../src/spotify.js";
const out = { playlists: {}, liked: [], top: {}, topArtists: {}, recent: [] };
for (const p of (await spotify.listPlaylists()).filter((p) => p.mine)) out.playlists[p.id] = await spotify.getPlaylist(p.id);
out.liked = await spotify.savedTracks();
for (const r of ["short_term", "medium_term", "long_term"]) { out.top[r] = await spotify.topTracks(r, 50); out.topArtists[r] = await spotify.topArtists(r, 50); }
out.recent = await spotify.recentlyPlayed(50);
const file = process.argv[2] ?? "library.json";
writeFileSync(file, JSON.stringify(out));
console.log(`${file}: ${Object.keys(out.playlists).length} playlists, ${out.liked.length} liked songs`);
