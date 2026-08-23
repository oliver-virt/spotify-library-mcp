#!/usr/bin/env bash
# Starts the HTTP server (if not running) and a Cloudflare quick tunnel, then prints the connector URL for claude.ai.
set -e
cd "$(dirname "$0")/.."
SECRET=$(grep '^MCP_SECRET=' .env | cut -d= -f2)
PORT=$(grep '^PORT=' .env | cut -d= -f2); PORT=${PORT:-8787}
curl -sf "http://127.0.0.1:$PORT/healthz" >/dev/null || { node src/http.js & sleep 1; }
LOG=$(mktemp)
cloudflared tunnel --url "http://127.0.0.1:$PORT" >"$LOG" 2>&1 &
for _ in $(seq 1 30); do
  URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$LOG" | head -1)
  [ -n "$URL" ] && break; sleep 1
done
[ -z "$URL" ] && { echo "tunnel failed:"; cat "$LOG"; exit 1; }
echo
echo "Add this as a custom connector in claude.ai (Settings → Connectors → Add custom connector):"
echo
echo "  $URL/$SECRET/mcp"
echo
echo "Leave this terminal open. Ctrl+C stops the tunnel."
wait
