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

## Next: run on a real iPhone signed into Apple Music (free trial is enough)
Needs a dev-signed build (add your team, enable automatic signing) — then tap "Run probe" and read the ✅/❌ list. The playlist.edit(foreign) row is the one that decides merge support.
