# spotify-library-mcp

Local MCP server + CLI for managing **your own** Spotify library. Single user, runs on your machine, PKCE auth (no client secret needed).

## Setup (one time)

1. https://developer.spotify.com/dashboard → **Create app**
   - Redirect URI: `http://127.0.0.1:8888/callback`
   - API: Web API
2. Copy the **Client ID** into `.env` (`SPOTIFY_CLIENT_ID=...`)
3. `npm install && npm run auth` → browser opens → approve → refresh token is written to `.env`
4. Verify: `node bin/spot.js playlists`

## Use from Claude Code

`.mcp.json` in this folder registers the server for this project. For every project:

```bash
claude mcp add --scope user spotify-library -- node /path/to/spotify-library-mcp/src/server.js
```

## CLI

```
node bin/spot.js playlists
node bin/spot.js playlist <id>
node bin/spot.js rename <id> "New name"
node bin/spot.js merge '{"sourceIds":["a","b"],"newName":"Merged","deleteSources":true}'
node bin/spot.js delete <id>
node bin/spot.js top short_term 20
node bin/spot.js summary            # whole library
node bin/spot.js summary <id>       # one playlist
node bin/spot.js find "Sultans"     # which playlists contain it
node bin/spot.js dupes
node bin/spot.js diff <a> <b>
node bin/spot.js snapshot weekly && node bin/spot.js changes
node bin/spot.js rediscover 4 50
```

## Tools

**Playlists** — list_playlists, get_playlist, create_playlist, update_playlist, add_tracks, remove_tracks, delete_playlist, merge_playlists
**Library** — get_saved_tracks, save_tracks, remove_saved_tracks, get_top_tracks, get_top_artists, get_recently_played
**Search** — search, find_track (artist-verified), get_search_budget, get_api_limits
**Analysis** (computed server-side, compact output — things Spotify users have asked for for a decade):
- `summarize_library` — liked songs in no playlist, stale/empty playlists, cross-playlist overlaps, decades, dupes
- `summarize_playlist` — runtime, top artists, decades, duplicates, over-representation
- `find_in_playlists` — "which of my playlists has this song?"
- `dedupe_report` — same artist+title ignoring remaster/live/edit suffixes, with ids to remove
- `playlist_diff` — only-in-A / only-in-B / shared
- `snapshot_library` · `list_snapshots` · `changes_since` — backup + "what changed since last week" (renames, adds, removes, likes)
- `rediscover` — liked years ago, absent from top tracks and recent plays; spread across artists

On my library these found: 233 liked songs in no playlist, 210 near-duplicates inside playlists, 1,113 forgotten likes from 2018–2021.

## Library scripts (how I reorganised 40 playlists → 9)

```
node scripts/pull.js library.json      # snapshot playlists + likes + tops
node scripts/build.js library.json     # file every track into genre collections (additive)
node scripts/moods.js                  # collapse genre collections into mood playlists
node scripts/curate.js library.json    # like picks, build Programming + שישי
node scripts/nostalgia.js library.json # 3-generation nostalgia
node scripts/explore.js library.json   # 🧭 Explore: ~400 new artists, many languages (search-heavy, resumable)
node scripts/genz.js                   # 🚗 Gen Z
node scripts/trending.js library.json  # 📈 Trending from live popularity
```

The artist lists in `scripts/classify.js` and friends are *my* taste — fork and edit. Every script is additive; deletions are separate explicit `spot delete` calls.

## Tests

`npm test` runs the whole flow against an in-memory mock Spotify (`test/mock-spotify.js`). No real credentials touched.

## claude.ai connector (remote)

`npm run tunnel` starts `src/http.js` (Streamable HTTP at `/<MCP_SECRET>/mcp`) plus a Cloudflare quick tunnel and prints the URL to paste into claude.ai → Settings → Connectors → Add custom connector (no OAuth; the secret path is the gate).

Quick tunnels get a new hostname each start. For a stable URL either run a named Cloudflare tunnel on your own domain, or deploy `src/http.js` behind your existing reverse proxy (e.g. the Nightscout box) with `MCP_SECRET`, `SPOTIFY_CLIENT_ID`, `SPOTIFY_REFRESH_TOKEN` in the environment.

## Spotify API limits (2026, apps created after Nov 2024) — baked in

| What | Status | Handled how |
|---|---|---|
| `/audio-features`, `/recommendations`, `related-artists` | removed | client throws a clear error before any request |
| batch `GET /tracks?ids=`, `/artists?ids=` | 403 | same; use single-item endpoints |
| artist `genres` field | gone | no genre data available, use your own knowledge |
| `/playlists/{id}/tracks` | renamed `/items`, entries under `item` | client uses new paths |
| `POST /users/{id}/playlists` | deprecated | `POST /me/playlists` |
| `PUT/DELETE /me/tracks` | deprecated | `/me/library?uris=` (max 20 per call, chunked) |
| name-only search | returns karaoke/covers | `find_track` tool verifies the artist |
| `/search` quota | **~1000/day per app → 429 with `retry-after ≈ 21h`** | persistent daily budget (default 800, `SPOTIFY_SEARCH_DAILY_CAP`), result cache, ban memory — see below |
| ~500 rapid calls | silent TLS-level drop for ~10 min (no 429) | 150 ms pacing + retry with backoff |

`get_api_limits` tool returns this list to the model; the server's MCP `instructions` carry the summary too.

### Search budget (learned 2026-08-23)

~1,000 `/search` calls in one day got this app a `429` with `retry-after: 75469` (21 h). The limit is **per app (client id)**, not per user, and it's the only quota we've hit that locks you out for a day.

What the server does about it (`src/budget.js`, state in `.search-budget.json`):
- counts searches per UTC day and refuses past `SPOTIFY_SEARCH_DAILY_CAP` (default 800) with a clear error
- caches every search result, so reruns of a script cost 0 searches
- remembers a ban from a long `retry-after` and fails fast until it expires — no 21-hour sleeps
- `get_search_budget` tool / `searchBudget()` report remaining, cached, banned-until

Bulk scripts (`scripts/explore.js`, `genz.js`, `trending.js`) print the budget first, stop cleanly at the cap, and resume on rerun (they skip what's already in the playlist). Plan ≈ 250 searches per script per day, or use a second Spotify app for bulk jobs.

Tomorrow's plan: ban lifts 2026-08-24 ~14:00 IDT → run `explore` (≈400, two days) or point a fresh client id at it.
