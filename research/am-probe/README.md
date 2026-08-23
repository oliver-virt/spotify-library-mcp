# Apple Music (MusicKit) feasibility probe

SwiftUI app that answers the questions deciding "Sorted for Apple Music":
1. read library with genre/playCount/skipCount/dateAdded
2. create playlist, add tracks, remove via edit()
3. edit a playlist created OUTSIDE the app (decides whether "merge" is possible)

Build & run: `xcodegen generate && xcodebuild -project SortedProbe.xcodeproj -scheme SortedProbe -destination "platform=iOS Simulator,name=iPhone 17 Pro" build`

## Simulator results (23 Aug 2026, iOS 27)
- authorize: PASS (.authorized, real permission prompt)
- library.read (MusicKit): FAIL `.unknown` — simulator has no Apple Music account
- mediaplayer.read: PASS (0 songs, empty library)
- playlist.create and beyond: stalls without an account → **device-only questions**

## Device results (iPhone 17 Pro, iOS 27, 24 Aug 2026) — VERDICT: GREEN LIGHT
- authorize: PASS
- library.read (MusicKit): PASS (201-song library, paginated)
- metadata: MusicKit `genreNames` empty on library songs; **MPMediaItem delivers genre ("Alternative"), playCount, skipCount, dateAdded** → read via MediaPlayer, classify with metadata
- playlist.create: PASS · playlist.add: PASS · playlist.remove via edit() on own playlist: PASS (2→1)
- playlist.add(foreign): FAIL MPErrorDomain Code=5 (Apple-curated "Favourite Songs")
- playlist.edit(foreign): FAIL, definitive: "Updating playlists are only allowed when updating a playlist that your app has created."

Conclusion: full organiser loop works (create/add/remove in app-owned playlists). No merge of pre-existing playlists — rebuild pattern + guided delete queue. Same constraint Song Sweeper ships under.

## Running it yourself
Needs a dev-signed build (add your team, enable automatic signing) — then tap "Run probe" and read the ✅/❌ list. The playlist.edit(foreign) row is the one that decides merge support.
