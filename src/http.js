// Remote (claude.ai connector) entry point: Streamable HTTP at /<MCP_SECRET>/mcp
import { createServer as httpServer } from "node:http";
import { timingSafeEqual } from "node:crypto";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { loadEnv } from "./env.js";
import { createServer } from "./tools.js";

loadEnv();
const secret = process.env.MCP_SECRET;
if (!secret || secret.length < 24) {
  console.error("MCP_SECRET must be set (>= 24 chars). Generate one: openssl rand -hex 24");
  process.exit(1);
}
const PORT = Number(process.env.PORT ?? 8787);
const HOST = process.env.HOST ?? "127.0.0.1";
const expected = Buffer.from(`/${secret}/mcp`);
const pathOk = (p) => { const b = Buffer.from(p); return b.length === expected.length && timingSafeEqual(b, expected); };

async function readJson(req) {
  let d = ""; for await (const c of req) d += c;
  return d ? JSON.parse(d) : undefined;
}

httpServer(async (req, res) => {
  const path = new URL(req.url, "http://x").pathname;
  if (path === "/healthz") return void res.end("ok");
  if (!pathOk(path)) { res.statusCode = 404; return void res.end(); }
  try {
    // Stateless: fresh server+transport per request. No session bookkeeping, survives restarts and tunnels.
    const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined });
    const server = createServer();
    await server.connect(transport);
    res.on("close", () => { transport.close(); server.close(); });
    await transport.handleRequest(req, res, req.method === "POST" ? await readJson(req) : undefined);
  } catch (e) {
    console.error(e);
    if (!res.headersSent) { res.statusCode = 500; res.end(JSON.stringify({ error: e.message })); }
  }
}).listen(PORT, HOST, () => console.log(`spotify-library MCP listening on http://${HOST}:${PORT}/<secret>/mcp`));
