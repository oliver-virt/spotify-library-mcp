// In-memory fake of the Spotify accounts + Web API subset we use. Exports start() for tests; runs standalone via `npm run test:mock`.
import { createServer } from "node:http";

export function start(port = 0) {
  const state = {
    me: { id: "oliver", display_name: "Oliver" },
    playlists: new Map(),
    saved: [],
    codes: new Map(),
    refreshToken: "rt-mock-1",
    accessTokens: new Set(),
    authedRequests: 0,
    searchHits: null,
    searchStatus: null,
    libraryCalls: [],
  };
  const mkTrack = (n) => ({ id: `t${n}`, uri: `spotify:track:t${n}`, name: `Track ${n}`, duration_ms: 1000 * n, artists: [{ name: `Artist ${n}` }], album: { name: `Album ${n}` } });
  const addPl = (id, name, ids) => state.playlists.set(id, { id, name, description: "", public: false, collaborative: false, owner: state.me, snapshot_id: "s1", external_urls: { spotify: `https://open.spotify.com/playlist/${id}` }, items: ids.map((n) => ({ added_at: "2024-01-01T00:00:00Z", item: mkTrack(n) })) });
  addPl("p1", "מחנס", [1, 2, 3]);
  addPl("p2", "Workout", [3, 4]);
  addPl("p3", "Workout copy", [4, 5]);
  state.saved = [1, 2, 7].map((n) => ({ added_at: "2024-01-01T00:00:00Z", track: mkTrack(n) }));

  const readBody = (req) => new Promise((r) => { let d = ""; req.on("data", (c) => (d += c)); req.on("end", () => r(d)); });
  const send = (res, code, obj) => { res.writeHead(code, { "Content-Type": "application/json" }); res.end(obj === null ? "" : JSON.stringify(obj)); };
  const page = (base, items, offset, limit) => ({ items: items.slice(offset, offset + limit), total: items.length, next: offset + limit < items.length ? `${base}?offset=${offset + limit}&limit=${limit}` : null });

  const server = createServer(async (req, res) => {
    const url = new URL(req.url, "http://x");
    const p = url.pathname;
    const raw = await readBody(req);
    const body = raw ? (raw.startsWith("{") ? JSON.parse(raw) : Object.fromEntries(new URLSearchParams(raw))) : {};

    // --- accounts ---
    if (p === "/authorize") {
      const code = "code-" + Math.random().toString(36).slice(2);
      state.codes.set(code, body.code_challenge ?? url.searchParams.get("code_challenge"));
      const back = new URL(url.searchParams.get("redirect_uri"));
      back.searchParams.set("code", code); back.searchParams.set("state", url.searchParams.get("state"));
      res.writeHead(302, { Location: back.href }); return res.end();
    }
    if (p === "/api/token") {
      if (body.grant_type === "authorization_code") {
        if (!state.codes.has(body.code) || !body.code_verifier) return send(res, 400, { error: "invalid_grant" });
        state.codes.delete(body.code);
        return send(res, 200, { access_token: "at-" + Date.now(), refresh_token: state.refreshToken, expires_in: 3600 });
      }
      if (body.grant_type === "refresh_token") {
        if (body.refresh_token !== state.refreshToken) return send(res, 400, { error: "invalid_grant" });
        const at = "at-" + Math.random().toString(36).slice(2); state.accessTokens.add(at);
        return send(res, 200, { access_token: at, expires_in: 3600 });
      }
      return send(res, 400, { error: "unsupported_grant_type" });
    }

    // --- api ---
    const auth = req.headers.authorization ?? "";
    if (!state.accessTokens.has(auth.replace("Bearer ", ""))) return send(res, 401, { error: { status: 401, message: "bad token" } });
    state.authedRequests++;
    const offset = Number(url.searchParams.get("offset") ?? 0), limit = Number(url.searchParams.get("limit") ?? 20);
    const plSummary = (pl) => ({ ...pl, items: { total: pl.items.length } });
    let m;
    if (p === "/v1/me") return send(res, 200, state.me);
    if (p === "/v1/me/playlists" && req.method === "GET") return send(res, 200, page(url.origin + p, [...state.playlists.values()].map(plSummary), offset, limit));
    if (p === "/v1/me/tracks") return send(res, 200, page(url.origin + p, state.saved, offset, limit));
    if (p === "/v1/me/top/tracks") return send(res, 200, { items: [mkTrack(1), mkTrack(3)] });
    if (p === "/v1/me/top/artists") return send(res, 200, { items: [{ id: "a1", name: "Artist 1", genres: ["pop"] }] });
    if (p === "/v1/me/player/recently-played") return send(res, 200, { items: [{ played_at: "2024-01-02T00:00:00Z", track: mkTrack(2) }] });
    if (p === "/v1/search" && state.searchStatus) { res.writeHead(state.searchStatus[0], { "retry-after": String(state.searchStatus[1]) }); return res.end(); }
    if (p === "/v1/search") return send(res, 200, { tracks: { items: state.searchHits ?? [mkTrack(9)] } });
    if (p === "/v1/me/library") {
      const uris = (url.searchParams.get("uris") ?? "").split(",").filter(Boolean);
      if (uris.length > 20) return send(res, 400, { error: { status: 400, message: "Too many uris requested" } });
      state.libraryCalls.push(uris);
      if (req.method === "PUT") for (const u of uris) state.saved.push({ added_at: "2026-01-01T00:00:00Z", track: mkTrack(u.split(":").pop().slice(1)) });
      if (req.method === "DELETE") { const rm = new Set(uris); state.saved = state.saved.filter((i) => !rm.has(i.track.uri)); }
      return send(res, 200, null);
    }
    if (p === "/v1/me/playlists" && req.method === "POST") {
      const id = "p" + (state.playlists.size + 1);
      addPl(id, body.name, []); Object.assign(state.playlists.get(id), { description: body.description, public: body.public });
      return send(res, 201, plSummary(state.playlists.get(id)));
    }
    if ((m = p.match(/^\/v1\/playlists\/([^/]+)$/))) {
      const pl = state.playlists.get(m[1]); if (!pl) return send(res, 404, { error: { status: 404, message: "not found" } });
      if (req.method === "PUT") { Object.assign(pl, body); return send(res, 200, null); }
      return send(res, 200, plSummary(pl));
    }
    if ((m = p.match(/^\/v1\/playlists\/([^/]+)\/items$/))) {
      const pl = state.playlists.get(m[1]); if (!pl) return send(res, 404, {});
      if (req.method === "GET") return send(res, 200, page(url.origin + p, pl.items, offset, limit));
      if (req.method === "POST") { for (const u of body.uris) pl.items.push({ added_at: "2024-01-03T00:00:00Z", item: mkTrack(u.split(":").pop().slice(1)) }); pl.snapshot_id += "+"; return send(res, 201, { snapshot_id: pl.snapshot_id }); }
      if (req.method === "DELETE") { const rm = new Set(body.items.map((t) => t.uri)); pl.items = pl.items.filter((i) => !rm.has(i.item.uri)); pl.snapshot_id += "-"; return send(res, 200, { snapshot_id: pl.snapshot_id }); }
    }
    if ((m = p.match(/^\/v1\/playlists\/([^/]+)\/followers$/)) && req.method === "DELETE") { state.playlists.delete(m[1]); return send(res, 200, null); }
    send(res, 404, { error: { status: 404, message: `mock: no route ${req.method} ${p}` } });
  });

  return new Promise((resolve) => server.listen(port, "127.0.0.1", () => resolve({ server, state, url: `http://127.0.0.1:${server.address().port}` })));
}

if (process.argv[1] && import.meta.url.endsWith(process.argv[1].split("/").pop())) {
  const { url } = await start(9999);
  console.log(`Mock Spotify on ${url}\n  SPOTIFY_ACCOUNTS_URL=${url} SPOTIFY_API_URL=${url}/v1 SPOTIFY_CLIENT_ID=mock`);
}
