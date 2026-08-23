// Build genre collections from Liked + all owned playlists. Additive only: creates/renames/adds, never deletes.
import { spotify } from "../src/spotify.js";
import { classify } from "./classify.js";
const o = JSON.parse((await import("node:fs")).readFileSync(process.argv[2], "utf8"));
// destination playlist per genre: existing id, or null → create
const DEST = {
  "Classic Rock": null, "Alt & Indie": null, "Rock": null, "Hip-Hop & Pop": null, "Israeli Rock": null, "Israeli Pop": null, "Unsorted": null,
  "Psytrance & EDM": "793TXkHK06vnWCkynGIoNm", // Electronic
  "Deutsch": "1OcDRUhYWqe6EpW6kh0cfV",          // Box → renamed Deutsch
  "Focus": "28VvQQMQSbo7ojE1P46ODG",            // DND ich arbeite → renamed Focus
};
const DESC = { "Classic Rock": "Filed by genre · built from Liked Songs", "Unsorted": "Liked songs the classifier couldn't place — triage me" };
const pool = new Map();
for (const t of [...o.liked, ...Object.values(o.playlists).flatMap((p) => p.tracks)]) if (!pool.has(t.id)) pool.set(t.id, t);
const buckets = {};
for (const t of pool.values()) (buckets[classify(t)] ??= []).push(t.id);
await spotify.updatePlaylist(DEST.Deutsch, { name: "Deutsch" });
await spotify.updatePlaylist(DEST.Focus, { name: "Focus" });
for (const [genre, ids] of Object.entries(buckets)) {
  let target = DEST[genre];
  if (!target) target = (await spotify.createPlaylist({ name: genre, description: DESC[genre] ?? "Filed by genre · built from Liked Songs" })).id;
  const r = await spotify.addTracks(target, ids);
  console.log(`${genre.padEnd(16)} → ${target}  +${r.added} (of ${ids.length})`);
}
