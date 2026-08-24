# Da Capo — product spec v2: the librarian (reframed 24 Aug 2026)

**Positioning:** A librarian for your Apple Music library, living on your phone. Ask — it proposes a plan — you approve. Formerly framed as a sort-wizard; the wizard is now one ask among many.

**Primary line:** "A librarian for your music. Ask. It's done."
**Trust line:** "It proposes. You approve. It can't touch what it didn't make. No server."
**Data hook:** "It knows the counts Apple hides."

## The asks (features as requests)
| Ask | Machinery | Status |
|---|---|---|
| "Sort my whole library" | scan → genre/decade/favorites/rediscover plan → apply | ✅ shipped (the wizard) |
| "How do I actually listen?" | report card: hidden play counts, genres, decades, health | ✅ shipped |
| "Find my duplicates" | fuzzy match → review-queue playlist | ✅ shipped |
| "What did I forget I loved?" | rediscover query with receipts (×N in 2023, silent since) | ✅ shipped (needs ask-surface) |
| "45 min for tonight, nothing sad" | filter-composition over genre/plays/era/duration | 🔜 agent v1 |
| "File my new songs" | diff since last scan → assign to existing Da Capo playlists | 🔜 agent v1; auto-weekly = Librarian tier |
| "Add more like X" | catalog search + library context | 🔜 agent v2 (needs cloud fallback) |

## Architecture of the agent
Foundation Models tool-calling (iOS 26+, Apple Intelligence). The model NEVER answers from music knowledge
(device probe 2026-08-23: unreliable) — it composes calls to deterministic tools:
`filter_library(genre, min/max_plays, added_range, duration_target)` · `create_playlist` · `refresh_playlist`
· `rediscover()` · `file_new_songs()` · `report()`. Every mutating result renders as a PLAN CARD; nothing applies without a tap.
Fallbacks: no Apple Intelligence → chips run the same tools with fixed intents (the current UI is the fallback).

## UX
Not a chat app. One Ask bar over the existing tabs + suggestion chips ("File new songs" · "Tonight's playlist" · "What did I forget?").
Answers are plan cards in the existing Swiss language. Approve = the existing apply path (idempotent, snapshot-safe).

## Retention (the librarian keeps working — Librarian tier $1.99/mo)
1. Widgets: health score · forgotten gem of the day (Airbuds/SongCapsule evidence)
2. Monthly report ritual: "Your August" card + one push (Receiptify ritual, monthly Wrapped)
3. Auto-file new songs weekly (Miximum staleness complaint)
4. Milestones: "Sultans of Swing hit ×100" (unique data: play counts)
5. "On this day you added…" (Lapse/Retro nostalgia mechanics)

## Pricing
Free: scan + report card, forever. **$6.99 once:** the great sort + all manual asks.
**Librarian $1.99/mo:** auto-file, monthly card, milestones, widgets. Cancel and keep everything created.

## Constraints (unchanged, now trust features)
Cannot delete songs, cannot edit foreign playlists (Apple rules) → "it can't touch what it didn't make."
On-device only, no account, no server. Apple Intelligence required for free-form asks; chips work everywhere.
