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

---

# UI spec v3: The Record Room (24 Aug 2026, evidence-based)

Direction chosen from generated concepts: **A — pixel scene + clean chat + receipts** (ui-a.png). B (full RPG chrome) rejected: legibility + game-cosplay risk. C (corner mascot) rejected: uncommitted.

## Structure — 3 tabs
1. **Store** — scene header ~300pt, Cap idling (bob/blink), collapses on scroll to slim status bar. Tappable props: crate→stats, notice board→report card, register→receipt history. Below: today's cards (new songs to file, dupes found, plans).
2. **Chat with Cap** — proposals as receipt cards with APPROVE/DECLINE (never bare bubbles), suggestion chips above composer (≤4), free-text never the only path.
3. **The Files** — report card, stamped receipts, history. Chat is ephemeral; cards persist here (Dot pattern).
Cross-links: every Store card deep-links to pre-seeded chat; every approved plan files its receipt.

## The receipt = universal artifact (Receiptify-validated)
Proposal → receipt; approve → stamped "PAID · CASHIER: CAP"; report card = long thermal receipt; all export Stories-sized (monospace, ruled separators, store header, total line).

## Cap's laws (Finch/Duolingo scars)
- Reward AFTER action, never gate before; reactions ≤5s; sprite-layer construction (body/head/arms/item) for cheap moods.
- Wants, not needs: no decay, no guilt. Notifications self-limit after being ignored.
- His speech IS the insight; tone = wry record clerk, dry, never saccharine.
- Paywall only after the plan is shown (Finch's #1 complaint = bill before bond).

## One ritual only (Lapse lesson)
Monthly report "prints overnight" → tear-off gesture in the morning. Everything else: standard iOS nav in retro chrome (wood dividers, price-tag chips, paper receipts).

## Typography
Pixel font: headers, Cap's short lines, receipt titles. SF Pro/SF Mono: all body & data (>~6 words). Pixel art at integer scales only.

## Asset pipeline (post-FLUX research, Aug 2026)
- Cap poses & scenes-with-Cap: **fal-ai/nano-banana-2 edit** with canon Cap image as reference ($0.08) — fixes cross-image character drift (seen in ui-a/b/c).
- True grid pixel scenes/sprites: **Retro Diffusion API** (grid-aligned, palette-limited, ~$0.01–0.18).
- Icons: **fal-ai/recraft/v4** (SVG, $0.04–0.08). FLUX schnell remains the cheap scratchpad.
