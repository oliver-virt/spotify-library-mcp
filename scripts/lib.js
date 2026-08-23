import { searchBudget } from "../src/spotify.js";
export function announceBudget(planned) {
  const b = searchBudget();
  console.log(`search budget: ${b.remaining}/${b.cap} left today, ${b.cached} cached${b.banned ? `, BANNED until ${b.bannedUntil}` : ""}`);
  if (b.banned) { console.log("stopping: search is banned."); process.exit(2); }
  if (planned > b.remaining) console.log(`note: ${planned} searches planned > ${b.remaining} left — will stop at the cap and resume on the next run.`);
}
export const isBudgetError = (e) => /budget exhausted|banned for this app|rate limit/.test(e.message);
