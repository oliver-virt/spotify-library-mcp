#!/usr/bin/env node
// Tiny CLI over the same client: `spot <command> [json-args]`
import { spotify } from "../src/spotify.js";
import * as A from "../src/analysis.js";

const [cmd, ...rest] = process.argv.slice(2);
const commands = {
  me: () => spotify.me(),
  playlists: () => spotify.listPlaylists(),
  playlist: (id) => spotify.getPlaylist(id),
  create: (name, description) => spotify.createPlaylist({ name, description }),
  rename: (id, name) => spotify.updatePlaylist(id, { name }),
  describe: (id, description) => spotify.updatePlaylist(id, { description }),
  add: (id, ...tracks) => spotify.addTracks(id, tracks),
  remove: (id, ...tracks) => spotify.removeTracks(id, tracks),
  delete: (id) => spotify.deletePlaylist(id),
  merge: (json) => spotify.mergePlaylists(JSON.parse(json)),
  saved: () => spotify.savedTracks(),
  search: (q, type, limit) => spotify.search(q, type, limit && Number(limit)),
  top: (range, limit) => spotify.topTracks(range, limit && Number(limit)),
  "top-artists": (range, limit) => spotify.topArtists(range, limit && Number(limit)),
  recent: (limit) => spotify.recentlyPlayed(limit && Number(limit)),
  summary: (id) => (id ? A.summarizePlaylist(id) : A.summarizeLibrary()),
  find: (q) => A.findInPlaylists(q),
  dupes: () => A.dedupeReport(),
  diff: (a, b) => A.playlistDiff(a, b),
  snapshot: (label) => A.snapshotLibrary(label),
  changes: (file) => A.changesSince(file),
  rediscover: (years, limit) => A.rediscover({ minYearsAgo: years && Number(years), limit: limit && Number(limit) }),
};
if (!commands[cmd]) {
  console.error("Usage: spot <" + Object.keys(commands).join("|") + "> [args]");
  process.exit(2);
}
try {
  const out = await commands[cmd](...rest);
  console.log(JSON.stringify(out ?? { ok: true }, null, 2));
} catch (e) {
  console.error(e.message);
  process.exit(1);
}
