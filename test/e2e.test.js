import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { spawn } from "node:child_process";
import { readFileSync, writeFileSync, existsSync, unlinkSync } from "node:fs";
import { join } from "node:path";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
import { start } from "./mock-spotify.js";
import { ROOT } from "../src/env.js";

let mock, env;
const envFile = join(ROOT, ".env");
let envBackup = null;

before(async () => {
  mock = await start();
  env = { ...process.env, SPOTIFY_ACCOUNTS_URL: mock.url, SPOTIFY_API_URL: mock.url + "/v1", SPOTIFY_CLIENT_ID: "mock", SPOTIFY_REDIRECT_URI: "http://127.0.0.1:8899/callback", NO_BROWSER: "1", SPOTIFY_BUDGET_FILE: join(mkdtempSync(join(tmpdir(), "budget-")), "b.json") };
  delete env.SPOTIFY_REFRESH_TOKEN;
  if (existsSync(envFile)) envBackup = readFileSync(envFile, "utf8");
  writeFileSync(envFile, "SPOTIFY_CLIENT_ID=mock\n");
});
after(() => {
  mock.server.close();
  if (envBackup === null) unlinkSync(envFile); else writeFileSync(envFile, envBackup);
});

test("auth script completes PKCE flow and writes refresh token to .env", async () => {
  const child = spawn("node", ["scripts/auth.js"], { cwd: ROOT, env });
  let out = "";
  const authUrl = await new Promise((resolve, reject) => {
    child.stdout.on("data", (d) => { out += d; const m = out.match(/https?:\/\/\S+/); if (m) resolve(m[0]); });
    child.on("exit", (c) => reject(new Error("auth exited early: " + c + out)));
  });
  const u = new URL(authUrl);
  assert.equal(u.searchParams.get("code_challenge_method"), "S256");
  assert.ok(u.searchParams.get("scope").includes("playlist-modify-private"));
  // Simulate the browser: hit mock /authorize, follow redirect to the local callback
  const r1 = await fetch(authUrl, { redirect: "manual" });
  assert.equal(r1.status, 302);
  const r2 = await fetch(r1.headers.get("location"));
  assert.equal(r2.status, 200);
  await new Promise((r) => child.on("exit", r));
  const saved = readFileSync(envFile, "utf8");
  assert.match(saved, /SPOTIFY_REFRESH_TOKEN=rt-mock-1/);
  env.SPOTIFY_REFRESH_TOKEN = "rt-mock-1";
});

test("MCP server over stdio: list/create/merge/rename/delete playlists", async () => {
  const client = new Client({ name: "test", version: "0" });
  await client.connect(new StdioClientTransport({ command: "node", args: ["src/server.js"], cwd: ROOT, env }));
  const call = async (name, args = {}) => { const r = await client.callTool({ name, arguments: args }); assert.ok(!r.isError, r.content[0].text); return JSON.parse(r.content[0].text); };

  const tools = (await client.listTools()).tools.map((t) => t.name);
  assert.ok(tools.includes("merge_playlists") && tools.includes("get_top_tracks"));

  let pls = await call("list_playlists");
  assert.equal(pls.length, 3);
  assert.equal(pls.find((p) => p.id === "p1").name, "מחנס");
  assert.equal(pls[0].mine, true);

  const full = await call("get_playlist", { playlist_id: "p2" });
  assert.deepEqual(full.tracks.map((t) => t.id), ["t3", "t4"]);

  const merged = await call("merge_playlists", { source_ids: ["p2", "p3"], new_name: "Workout (merged)", delete_sources: true });
  assert.equal(merged.unique_tracks_seen, 3);
  assert.equal(merged.added, 3);
  pls = await call("list_playlists");
  assert.deepEqual(pls.map((p) => p.name).sort(), ["Workout (merged)", "מחנס"]);
  const mergedFull = await call("get_playlist", { playlist_id: merged.targetId });
  assert.deepEqual(mergedFull.tracks.map((t) => t.id).sort(), ["t3", "t4", "t5"]);

  // dedupe on add
  const again = await call("add_tracks", { playlist_id: merged.targetId, track_ids: ["t5", "t6"] });
  assert.equal(again.added, 1);
  await call("remove_tracks", { playlist_id: merged.targetId, track_ids: ["t6"] });

  await call("update_playlist", { playlist_id: "p1", name: "מחנס 2024", description: "renamed" });
  assert.equal((await call("get_playlist", { playlist_id: "p1" })).name, "מחנס 2024");

  assert.equal((await call("get_saved_tracks")).length, 3);
  assert.equal((await call("get_top_tracks", { time_range: "short_term" })).length, 2);
  assert.equal((await call("search", { query: "x" }))[0].id, "t9");

  await call("delete_playlist", { playlist_id: "p1" });
  assert.equal((await call("list_playlists")).length, 1);
  await client.close();
});

test("CLI works with the same env", async () => {
  const out = await new Promise((resolve, reject) => {
    const c = spawn("node", ["bin/spot.js", "me"], { cwd: ROOT, env });
    let s = ""; c.stdout.on("data", (d) => (s += d)); c.on("exit", (code) => (code ? reject(new Error("exit " + code)) : resolve(s)));
  });
  assert.equal(JSON.parse(out).id, "oliver");
});
