import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { start } from "./mock-spotify.js";

let mock, spotify, budget;
before(async () => {
  mock = await start();
  process.env.SPOTIFY_BUDGET_FILE = join(mkdtempSync(join(tmpdir(), "budget-")), "b.json");
  Object.assign(process.env, { SPOTIFY_ACCOUNTS_URL: mock.url, SPOTIFY_API_URL: mock.url + "/v1", SPOTIFY_CLIENT_ID: "mock", SPOTIFY_REFRESH_TOKEN: "rt-mock-1", SPOTIFY_MIN_GAP_MS: "0", SPOTIFY_SEARCH_DAILY_CAP: "3" });
  ({ spotify } = await import("../src/spotify.js"));
  ({ budget } = await import("../src/budget.js"));
  budget._reset();
});
after(() => mock.server.close());

test("search spends budget, caches repeats (no network), and stops at the cap", async () => {
  const n0 = mock.state.authedRequests;
  await spotify.search("a"); await spotify.search("a"); await spotify.search("a");
  assert.equal(mock.state.authedRequests - n0, 1, "repeat query served from cache");
  assert.equal(budget.status().used, 1);
  await spotify.search("b"); await spotify.search("c");
  assert.deepEqual([budget.status().used, budget.status().remaining], [3, 0]);
  await assert.rejects(spotify.search("d"), /budget exhausted/);
  await assert.doesNotReject(spotify.search("a"), "cached queries still work when exhausted");
});

test("a long 429 on /search is remembered as a ban and fails fast without network", async () => {
  budget._reset();
  mock.state.searchStatus = [429, 80000];
  const n0 = mock.state.authedRequests;
  await assert.rejects(spotify.search("x"), /rate limit.*22\.2h/);
  mock.state.searchStatus = null;
  await assert.rejects(spotify.search("y"), /banned for this app until/);
  assert.equal(mock.state.authedRequests - n0, 1, "second call never hit the network");
  assert.equal(budget.status().banned, true);
});
