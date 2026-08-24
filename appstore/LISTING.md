# Da Capo — App Store listing (draft 1)

**Name** (≤30): Da Capo: Organize Your Music
**Subtitle** (≤30): Sort library, find duplicates
**Keywords** (≤100): apple,playlist,maker,genre,decade,stats,plays,count,cleaner,tidy,rediscover
**Promo text** (≤170): Your Apple Music library, finally organized. One scan builds playlists by genre, decade and mood — and shows you the play counts Apple hides. On your phone only.

**Description:**
Your music library is a mess. Nine years of saved songs, no order, duplicates everywhere, and thousands of tracks you forgot you loved.

Da Capo fixes it in 30 seconds — entirely on your iPhone.

SCAN
One tap reads your library: every song, genre, play count and the date you added it. Nothing is uploaded. There is no server.

SEE
• Your library, diagnosed: unfiled songs, never-played, duplicates, forgotten favorites
• The play counts Apple doesn't show on iPhone
• Genres, decades and your most-played artists
• A health score — and a shareable report card, any day of the year

SORT
Da Capo proposes playlists from your actual music — by genre, by decade, your real favorites, and the songs you loved and lost. Rename anything, switch off what you don't want, tap once. They appear in Apple Music, filled and named.

Re-run any time: Da Capo refreshes its own playlists instead of duplicating them.

WHAT IT WILL NEVER DO
Da Capo cannot delete your songs or edit your playlists — by Apple's own rules, not just ours. It reads your library and creates its own playlists. That's the whole deal.

Duplicates? No app can delete them for you. Da Capo finds every one and gathers them in a single review playlist, so cleaning up in Music takes a minute instead of an afternoon.

One purchase. Not per month. The scan and report card are free forever.

Requires an Apple Music subscription and iOS 17 or later. Mood playlists use Apple Intelligence on supported devices.


---

## Support URL
https://oliver-virt.github.io/spotify-library-mcp/support.html
## Privacy Policy URL
https://oliver-virt.github.io/spotify-library-mcp/privacy.html

## App Review notes (paste into ASC)
Da Capo organizes the user's Apple Music library on-device. To test fully you need an Apple Music subscription on the test device; without one the app explains the requirement gracefully. A full demo video (scan → report → plan → playlists created in Apple Music → purchase → restore) is linked here: [UNLISTED VIDEO LINK — record during QA].

Notes: (1) The app creates its own playlists in the user's library. It cannot delete songs or modify playlists it didn't create — Apple's MediaPlayer/MusicKit APIs do not permit this, and the app says so explicitly. (2) The free tier includes the full scan and report card; the one-time non-consumable IAP "Da Capo Lifetime" (com.olivervirt.dacapo.unlock) unlocks playlist creation. The paywall appears only after the user has seen their proposed plan. Restore is implemented via AppStore.sync. (3) The chat-style interface runs fixed, deterministic intents — there is no chatbot service, no LLM server; the optional mood feature uses on-device Apple Intelligence only. (4) No account, no login, no data collection, no network calls.

## Screenshot plan (6.9" 1320×2868, portrait, 6 shots)
1. Sorted playlists inside Apple Music — "Your library. Finally sorted."
2. Report card — "The play counts Apple hides."
3. Plan card — "It proposes. You approve."
4. Duplicates gathered — "Finds every duplicate."
5. Forgotten favorites — "×121 in 2023. Silent since."
6. "One purchase. Not per month."
