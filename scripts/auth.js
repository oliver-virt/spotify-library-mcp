// One-time PKCE login: opens your browser, catches the callback, writes SPOTIFY_REFRESH_TOKEN into .env
import { createServer } from "node:http";
import { randomBytes, createHash } from "node:crypto";
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { exec } from "node:child_process";
import { loadEnv, ROOT } from "../src/env.js";

loadEnv();
const ACCOUNTS = process.env.SPOTIFY_ACCOUNTS_URL ?? "https://accounts.spotify.com";
const clientId = process.env.SPOTIFY_CLIENT_ID;
const redirectUri = process.env.SPOTIFY_REDIRECT_URI ?? "http://127.0.0.1:8888/callback";
if (!clientId) {
  console.error("SPOTIFY_CLIENT_ID is not set. Copy .env.example to .env and fill it in.");
  process.exit(1);
}

export const SCOPES = [
  "playlist-read-private",
  "playlist-read-collaborative",
  "playlist-modify-private",
  "playlist-modify-public",
  "user-library-read",
  "user-library-modify",
  "user-top-read",
  "user-read-recently-played",
  "user-read-private",
];

const b64url = (b) => b.toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const verifier = b64url(randomBytes(48));
const challenge = b64url(createHash("sha256").update(verifier).digest());
const state = b64url(randomBytes(12));

const url = new URL(`${ACCOUNTS}/authorize`);
url.search = new URLSearchParams({
  client_id: clientId,
  response_type: "code",
  redirect_uri: redirectUri,
  scope: SCOPES.join(" "),
  code_challenge_method: "S256",
  code_challenge: challenge,
  state,
}).toString();

const { port, pathname } = new URL(redirectUri);
const server = createServer(async (req, res) => {
  const u = new URL(req.url, redirectUri);
  if (u.pathname !== pathname) return void (res.statusCode = 404, res.end());
  try {
    if (u.searchParams.get("state") !== state) throw new Error("state mismatch");
    if (u.searchParams.get("error")) throw new Error(u.searchParams.get("error"));
    const code = u.searchParams.get("code");
    const r = await fetch(`${ACCOUNTS}/api/token`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ grant_type: "authorization_code", code, redirect_uri: redirectUri, client_id: clientId, code_verifier: verifier }),
    });
    if (!r.ok) throw new Error(`token exchange ${r.status}: ${await r.text()}`);
    const { refresh_token } = await r.json();
    saveToken(refresh_token);
    res.end("<h2>Spotify connected. You can close this tab.</h2>");
    console.log("Refresh token saved to .env");
    setTimeout(() => process.exit(0), 200);
  } catch (e) {
    res.statusCode = 500;
    res.end(`Auth failed: ${e.message}`);
    console.error(e.message);
    setTimeout(() => process.exit(1), 200);
  }
});

function saveToken(tok) {
  const file = join(ROOT, ".env");
  let text = existsSync(file) ? readFileSync(file, "utf8") : "";
  if (/^SPOTIFY_REFRESH_TOKEN=.*$/m.test(text)) text = text.replace(/^SPOTIFY_REFRESH_TOKEN=.*$/m, `SPOTIFY_REFRESH_TOKEN=${tok}`);
  else text += `${text.endsWith("\n") || !text ? "" : "\n"}SPOTIFY_REFRESH_TOKEN=${tok}\n`;
  writeFileSync(file, text);
}

server.listen(Number(port) || 80, "127.0.0.1", () => {
  console.log("Open this URL in your browser if it didn't open automatically:\n\n" + url.href + "\n");
  if (!process.env.NO_BROWSER) exec(`open "${url.href}"`);
});
