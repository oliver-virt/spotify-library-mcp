import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn } from "node:child_process";
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";
import { start } from "./mock-spotify.js";
import { ROOT } from "../src/env.js";

const SECRET = "test-secret-abcdefghijklmnopqrstuvwxyz";
let mock, child;
const base = "http://127.0.0.1:8790";

before(async () => {
  mock = await start();
  const env = { ...process.env, SPOTIFY_ACCOUNTS_URL: mock.url, SPOTIFY_API_URL: mock.url + "/v1", SPOTIFY_CLIENT_ID: "mock", SPOTIFY_REFRESH_TOKEN: "rt-mock-1", MCP_SECRET: SECRET, PORT: "8790", SPOTIFY_BUDGET_FILE: join(mkdtempSync(join(tmpdir(), "budget-")), "b.json") };
  child = spawn("node", ["src/http.js"], { cwd: ROOT, env, stdio: ["ignore", "pipe", "inherit"] });
  await new Promise((r) => child.stdout.on("data", (d) => d.toString().includes("listening") && r()));
});
after(() => { child.kill(); mock.server.close(); });

test("wrong or missing secret → 404, health ok", async () => {
  assert.equal((await fetch(`${base}/healthz`)).status, 200);
  assert.equal((await fetch(`${base}/mcp`, { method: "POST" })).status, 404);
  assert.equal((await fetch(`${base}/nope/mcp`, { method: "POST" })).status, 404);
});

test("Streamable HTTP client can list tools and call them", async () => {
  const client = new Client({ name: "claude-ai-sim", version: "0" });
  await client.connect(new StreamableHTTPClientTransport(new URL(`${base}/${SECRET}/mcp`)));
  const tools = (await client.listTools()).tools.map((t) => t.name);
  assert.ok(tools.includes("list_playlists") && tools.includes("merge_playlists"));
  const r = await client.callTool({ name: "list_playlists", arguments: {} });
  const pls = JSON.parse(r.content[0].text);
  assert.equal(pls.length, 3);
  assert.equal(pls[0].name, "מחנס");
  const up = await client.callTool({ name: "update_playlist", arguments: { playlist_id: "p1", name: "Renamed" } });
  assert.ok(!up.isError);
  assert.equal(JSON.parse((await client.callTool({ name: "get_playlist", arguments: { playlist_id: "p1" } })).content[0].text).name, "Renamed");
  await client.close();
});
