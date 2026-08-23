import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { start } from "./mock-spotify.js";

let mock, spotify, api;
before(async () => {
  mock = await start();
  Object.assign(process.env, { SPOTIFY_ACCOUNTS_URL: mock.url, SPOTIFY_API_URL: mock.url + "/v1", SPOTIFY_CLIENT_ID: "mock", SPOTIFY_REFRESH_TOKEN: "rt-mock-1", SPOTIFY_MIN_GAP_MS: "0", SPOTIFY_BUDGET_FILE: join(mkdtempSync(join(tmpdir(), "budget-")), "b.json") });
  ({ spotify, api } = await import("../src/spotify.js"));
});
after(() => mock.server.close());

test("removed/renamed endpoints fail fast with a helpful message, before hitting the network", async () => {
  const before = mock.state.authedRequests;
  for (const p of ["/audio-features/x", "/recommendations", "/artists/a/related-artists", "/tracks", "/playlists/p1/tracks", "/users/u/playlists"])
    await assert.rejects(api("GET", p), /Spotify API limit/);
  await assert.rejects(api("PUT", "/me/tracks"), /me\/library/);
  assert.equal(mock.state.authedRequests, before, "no request should have been sent");
  await assert.doesNotReject(api("GET", "/me/tracks", { query: { limit: 1 } }), "reading likes still works");
});

test("find_track rejects karaoke/cover mismatches; save/remove likes use /me/library in ≤20 chunks", async () => {
  mock.state.searchHits = [
    { id: "k1", uri: "spotify:track:k1", name: "Starburster", artists: [{ name: "Hit The Button Karaoke" }], album: { name: "Karaoke Hits" } },
    { id: "r1", uri: "spotify:track:r1", name: "Starburster", artists: [{ name: "Fontaines D.C." }], album: { name: "Romance" } },
  ];
  const t = await spotify.findTrack("Starburster", "Fontaines D.C.");
  assert.equal(t.id, "r1");
  assert.equal(await spotify.findTrack("Starburster", "Nobody"), null);
  const ids = Array.from({ length: 45 }, (_, i) => `t${i}`);
  assert.deepEqual(await spotify.saveTracks(ids), { saved: 45 });
  assert.deepEqual(mock.state.libraryCalls.map((c) => c.length), [20, 20, 5]);
  assert.equal(mock.state.saved.length, 3 + 45);
  await spotify.removeSavedTracks(["t0", "t44"]);
  assert.equal(mock.state.saved.length, 3 + 43);
});
