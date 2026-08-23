// Persistent /search budget + ban memory. Spotify gives new apps roughly 1000 searches/day per app;
// crossing it returns 429 with retry-after ≈ 21h. State lives in .search-budget.json (git-ignored).
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { ROOT } from "./env.js";

const FILE = process.env.SPOTIFY_BUDGET_FILE ?? join(ROOT, ".search-budget.json");
export const DAILY_CAP = Number(process.env.SPOTIFY_SEARCH_DAILY_CAP ?? 800); // safety margin under ~1000
const CACHE_MAX = 5000;

function load() {
  const empty = { day: today(), used: 0, bannedUntil: 0, cache: {} };
  if (!existsSync(FILE)) return empty;
  try { const s = JSON.parse(readFileSync(FILE, "utf8")); return s.day === today() ? { ...empty, ...s } : { ...empty, bannedUntil: s.bannedUntil ?? 0, cache: s.cache ?? {} }; }
  catch { return empty; }
}
const today = () => new Date().toISOString().slice(0, 10);
let state = load();
const save = () => writeFileSync(FILE, JSON.stringify(state));

export const budget = {
  status() {
    const banned = state.bannedUntil > Date.now();
    return { day: state.day, used: state.used, cap: DAILY_CAP, remaining: Math.max(0, DAILY_CAP - state.used), banned, bannedUntil: banned ? new Date(state.bannedUntil).toISOString() : null, cached: Object.keys(state.cache).length };
  },
  // Throws before any network call if a ban is active or the cap is reached.
  check() {
    const s = this.status();
    if (s.banned) throw new Error(`Spotify /search is banned for this app until ${s.bannedUntil} (429 retry-after). Use another client id or wait.`);
    if (s.remaining <= 0) throw new Error(`Daily /search budget exhausted (${s.used}/${s.cap}). Resets at midnight UTC; raise SPOTIFY_SEARCH_DAILY_CAP at your own risk.`);
  },
  spend() { state.used++; save(); },
  ban(seconds) { state.bannedUntil = Date.now() + seconds * 1000; save(); },
  cacheGet(key) { return state.cache[key]; },
  cacheSet(key, val) {
    state.cache[key] = val;
    const keys = Object.keys(state.cache);
    if (keys.length > CACHE_MAX) for (const k of keys.slice(0, keys.length - CACHE_MAX)) delete state.cache[k];
    save();
  },
  _reset() { state = { day: today(), used: 0, bannedUntil: 0, cache: {} }; save(); },
};
