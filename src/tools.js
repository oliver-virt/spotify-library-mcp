import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";

import { z } from "zod";
import { spotify, searchBudget } from "./spotify.js";

export function createServer() {
const server = new McpServer({ name: "spotify-library", version: "1.1.0" }, { instructions: `Spotify Web API limits (2026, new apps) baked into this server:
- No audio-features, recommendations, related-artists, or batch /tracks|/artists. Artist objects have no genres. Use your own music knowledge + search.
- search is name-based and returns karaoke/covers freely: use find_track (artist-verified) when you know the artist.
- Playlist item endpoints are /items; saving likes uses /me/library (20 per call). All handled internally.
- /search has a per-app daily budget (~1000/day → 429 with retry-after ≈ 21h). This server enforces a cap (default 800/day), caches results, and remembers bans. Call get_search_budget before bulk work; find_track/search throw a clear error when exhausted.
- Playlists cannot be deleted, only unfollowed (delete_playlist). Owned playlists unfollowed are gone.` });
const json = (data) => ({ content: [{ type: "text", text: JSON.stringify(data, null, 2) }] });
const tool = (name, description, schema, fn) =>
  server.registerTool(name, { description, inputSchema: schema }, async (args) => {
    try { return json(await fn(args)); }
    catch (e) { return { isError: true, content: [{ type: "text", text: e.message }] }; }
  });

tool("list_playlists", "List all playlists in the user's library (owned and followed).", {}, () => spotify.listPlaylists());
tool("get_playlist", "Get a playlist's details and its full track list.", { playlist_id: z.string() }, ({ playlist_id }) => spotify.getPlaylist(playlist_id));
tool("create_playlist", "Create a new playlist for the user.",
  { name: z.string(), description: z.string().optional(), public: z.boolean().optional().default(false) },
  ({ name, description, public: isPublic }) => spotify.createPlaylist({ name, description, isPublic }));
tool("update_playlist", "Rename a playlist or change its description/visibility.",
  { playlist_id: z.string(), name: z.string().optional(), description: z.string().optional(), public: z.boolean().optional() },
  ({ playlist_id, ...d }) => spotify.updatePlaylist(playlist_id, { name: d.name, description: d.description, isPublic: d.public }).then(() => ({ ok: true })));
tool("add_tracks", "Add tracks (ids or spotify:track: URIs) to a playlist, skipping ones already present.",
  { playlist_id: z.string(), track_ids: z.array(z.string()).min(1) }, ({ playlist_id, track_ids }) => spotify.addTracks(playlist_id, track_ids));
tool("remove_tracks", "Remove tracks from a playlist.",
  { playlist_id: z.string(), track_ids: z.array(z.string()).min(1) }, ({ playlist_id, track_ids }) => spotify.removeTracks(playlist_id, track_ids));
tool("delete_playlist", "Remove a playlist from the user's library (unfollow). Irreversible for owned playlists.",
  { playlist_id: z.string() }, ({ playlist_id }) => spotify.deletePlaylist(playlist_id).then(() => ({ ok: true })));
tool("merge_playlists", "Merge several playlists into one (existing target or a new one), deduplicating tracks. Optionally delete sources.",
  { source_ids: z.array(z.string()).min(1), target_id: z.string().optional(), new_name: z.string().optional(), delete_sources: z.boolean().optional().default(false) },
  ({ source_ids, target_id, new_name, delete_sources }) => spotify.mergePlaylists({ sourceIds: source_ids, targetId: target_id, newName: new_name, deleteSources: delete_sources }));
tool("find_track", "Find one track, verifying the artist is on the result (avoids karaoke/cover mismatches). Returns null if no verified match.",
  { track: z.string(), artist: z.string() }, ({ track, artist }) => spotify.findTrack(track, artist));
tool("save_tracks", "Add tracks to the user's Liked Songs.", { track_ids: z.array(z.string()).min(1).max(200) }, ({ track_ids }) => spotify.saveTracks(track_ids));
tool("remove_saved_tracks", "Remove tracks from Liked Songs.", { track_ids: z.array(z.string()).min(1).max(200) }, ({ track_ids }) => spotify.removeSavedTracks(track_ids));
tool("get_search_budget", "Remaining /search calls for today, cache size, and whether a Spotify search ban is active. Check before bulk searching.", {}, async () => searchBudget());
tool("get_api_limits", "What this Spotify app can and cannot do (endpoints removed/renamed by Spotify for new apps).", {}, async () => ({
  search_budget: searchBudget(),
  removed: ["audio-features (no energy/tempo/danceability)", "recommendations", "related-artists", "batch GET /tracks, /artists, /albums", "artist genres field"],
  renamed: { "/playlists/{id}/tracks": "/playlists/{id}/items", "/users/{id}/playlists": "POST /me/playlists", "/me/tracks": "/me/library (20 uris/call)" },
  pacing: "150ms min gap. /search: ~1000 calls/day → 429 with retry-after ≈ 21h (per app). Client throws on bans > 60s.",
  playlists: "no delete; unfollow only",
}));
tool("get_saved_tracks", "All tracks the user has Liked.", {}, () => spotify.savedTracks());
tool("search", "Search Spotify.", { query: z.string(), type: z.enum(["track", "artist", "album", "playlist"]).default("track"), limit: z.number().int().min(1).max(50).default(10) },
  ({ query, type, limit }) => spotify.search(query, type, limit));
tool("get_top_tracks", "The user's most-played tracks.", { time_range: z.enum(["short_term", "medium_term", "long_term"]).default("medium_term"), limit: z.number().int().min(1).max(50).default(50) },
  ({ time_range, limit }) => spotify.topTracks(time_range, limit));
tool("get_top_artists", "The user's most-played artists.", { time_range: z.enum(["short_term", "medium_term", "long_term"]).default("medium_term"), limit: z.number().int().min(1).max(50).default(50) },
  ({ time_range, limit }) => spotify.topArtists(time_range, limit));
tool("get_recently_played", "Recently played tracks.", { limit: z.number().int().min(1).max(50).default(50) }, ({ limit }) => spotify.recentlyPlayed(limit));

return server;
}
