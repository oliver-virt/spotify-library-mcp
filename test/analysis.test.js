import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { start } from "./mock-spotify.js";

let mock, spotify, A;
before(async () => {
  mock = await start();
  const dir = mkdtempSync(join(tmpdir(), "analysis-"));
  Object.assign(process.env, { SPOTIFY_ACCOUNTS_URL: mock.url, SPOTIFY_API_URL: mock.url + "/v1", SPOTIFY_CLIENT_ID: "mock", SPOTIFY_REFRESH_TOKEN: "rt-mock-1", SPOTIFY_MIN_GAP_MS: "0", SPOTIFY_BUDGET_FILE: join(dir, "b.json"), SPOTIFY_SNAPSHOT_DIR: join(dir, "snaps"), SPOTIFY_INDEX_TTL_MS: "0" });
  ({ spotify } = await import("../src/spotify.js"));
  A = await import("../src/analysis.js");
});
after(() => mock.server.close());

test("summaries, find, dedupe, diff compute over the library", async () => {
  const lib = await A.summarizeLibrary();
  assert.equal(lib.playlists, 3);
  assert.equal(lib.liked, 3);
  assert.equal(lib.liked_in_no_playlist, 1, "t7 is liked but in no playlist");
  assert.deepEqual(lib.overlaps, [], "only 1 shared track between p2/p3 (<3 threshold)");
  const p = await A.summarizePlaylist("p1");
  assert.equal(p.tracks, 3); assert.ok(p.runtime); assert.equal(p.distinct_artists, 3); assert.ok(Object.keys(p.decades).length >= 1);
  const f = await A.findInPlaylists("Track 3");
  assert.deepEqual(f.matches.map((m) => m.playlist).sort(), ["Workout", "מחנס"]);
  await spotify.addTracks("p2", ["t3"], { dedupe: false });
  const d = await A.dedupeReport();
  assert.equal(d.duplicates_within_playlists, 1);
  assert.equal(d.details.Workout[0].name, "Track 3");
  const diff = await A.playlistDiff("p2", "p3");
  assert.equal(diff.shared, 1);
  assert.deepEqual(diff.only_in_b.map((t) => t.id), ["t5"]);
});

test("snapshot → change → changes_since reports exactly the delta", async () => {
  const s = await A.snapshotLibrary("test");
  assert.equal(s.playlists, 3);
  await spotify.updatePlaylist("p1", { name: "Renamed" });
  await spotify.addTracks("p1", ["t9"]);
  await spotify.deletePlaylist("p3");
  await spotify.saveTracks(["t8"]);
  const c = await A.changesSince();
  const p1 = c.playlists.find((p) => p.name === "Renamed");
  assert.equal(p1.renamed_from, "מחנס");
  assert.deepEqual(p1.added, ["Track 9 – Artist 9"]);
  assert.ok(c.playlists.find((p) => p.status === "deleted"));
  assert.deepEqual(c.liked.added, ["Track 8 – Artist 8"]);
});

test("rediscover returns old likes absent from top/recent", async () => {
  const r = await A.rediscover({ minYearsAgo: 1 });
  // liked: t1,t2,t7 (2024) + t8 (2026). top tracks mock: t1,t3. recent: t2. → only t7 qualifies
  assert.deepEqual(r.tracks.map((t) => t.id), ["t7"]);
});
