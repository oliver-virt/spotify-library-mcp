import Foundation
import MusicKit

/// "Bring music in" — Apple's own recommendations + charts, filtered against what the user already owns.
struct NewSong: Identifiable {
    let id: String
    let title: String
    let artist: String
    let reason: String
    let song: Song
}

@MainActor
final class Discovery: ObservableObject {
    @Published var running = false
    @Published var phase = ""
    @Published var found: [NewSong] = []
    @Published var errorText: String?

    /// Five sources, best first:
    ///  1. New releases from artists you actually own
    ///  2. Songs by those artists you somehow don't have
    ///  3. Top songs from similar artists
    ///  4. Apple's personal recommendations (library-recycled sections last)
    ///  5. Charts, only if still thin
    func run(owned: Set<String>, topArtists: [String], prefs: DiscoveryPrefs = .load()) async {
        guard !running else { return }
        running = true; defer { running = false }
        errorText = nil; found = []
        var seen = Set<String>()
        let handled = Self.handled

        let blocked = Taste.blockedArtists
        let wanted = Set(prefs.genres.map { $0.lowercased() })
        func consider(_ s: Song, _ reason: String) {
            let key = Self.key(s.artistName, s.title)
            guard !owned.contains(key), !seen.contains(key), !handled.contains(key),
                  !blocked.contains(s.artistName.lowercased()) else { return }
            if !wanted.isEmpty {
                let gs = Set(s.genreNames.map { $0.lowercased() })
                guard !gs.isDisjoint(with: wanted) else { return }
            }
            seen.insert(key)
            found.append(NewSong(id: s.id.rawValue, title: s.title, artist: s.artistName, reason: reason, song: s))
        }

        // --- 1 & 2 & 3: build out from the artists in the library ---
        let needArtistWork = prefs.newFromArtists || prefs.deepCuts || prefs.similarArtists
        for name in (needArtistWork ? Array(topArtists.prefix(12)) : []) {
            if found.count >= 40 { break }
            phase = "Looking into \(name)…"
            guard let artist = try? await withDeadline(seconds: 10, {
                var r = MusicCatalogSearchRequest(term: name, types: [Artist.self])
                r.limit = 1
                return try await r.response().artists.first
            }) ?? nil else { continue }

            // new release they may have missed
            if prefs.newFromArtists, let full = try? await artist.with([.latestRelease]),
               let album = full.latestRelease,
               let tracks = try? await album.with(.tracks) {
                for t in (tracks.tracks ?? []).prefix(3) {
                    if case .song(let song) = t { consider(song, "New from \(name)") }
                }
            }
            // songs by an artist they own but don't have
            if prefs.deepCuts, let full = try? await artist.with([.topSongs]) {
                for song in (full.topSongs ?? []).prefix(4) { consider(song, "You own \(name) — not this one") }
            }
            // neighbours
            if prefs.similarArtists, let full = try? await artist.with([.similarArtists]) {
                for similar in (full.similarArtists ?? []).prefix(2) {
                    if let sf = try? await similar.with([.topSongs]) {
                        for song in (sf.topSongs ?? []).prefix(2) { consider(song, "Because you like \(name)") }
                    }
                }
            }
            try? await Task.sleep(for: .milliseconds(120))
        }

        // --- 4: Apple's own recommendations, library-recycled sections last ---
        if prefs.appleRecs, found.count < 30 {
            phase = "Reading your recommendations…"
            do {
                let res = try await withDeadline(seconds: 20) {
                    try await MusicPersonalRecommendationsRequest().response()
                }
                let recycled = ["made for you", "heavy rotation", "replay", "recently played",
                                "favorites", "top songs", "listen again"]
                let ranked = res.recommendations.sorted { a, b in
                    let ra = recycled.contains { (a.title ?? "").lowercased().contains($0) }
                    let rb = recycled.contains { (b.title ?? "").lowercased().contains($0) }
                    return !ra && rb
                }
                for rec in ranked {
                    let label = rec.title ?? "Recommended for you"
                    if recycled.contains(where: { label.lowercased().contains($0) }) { continue }
                    phase = "Going through \(label.lowercased())…"
                    for item in rec.items.prefix(10) {
                        switch item {
                        case .album(let a):
                            if let full = try? await a.with(.tracks) {
                                for t in (full.tracks ?? []).prefix(2) { if case .song(let s) = t { consider(s, label) } }
                            }
                        case .playlist(let p):
                            if let full = try? await p.with(.tracks) {
                                for t in (full.tracks ?? []).prefix(3) { if case .song(let s) = t { consider(s, label) } }
                            }
                        default: break
                        }
                        if found.count >= 40 { break }
                    }
                    if found.count >= 40 { break }
                }
            } catch { errorText = "Couldn't read recommendations: \(error.localizedDescription)" }
        }

        // --- 5: charts as a last resort ---
        if prefs.charts || found.count < 8 {
            phase = "Checking what's big right now…"
            do {
                var req = MusicCatalogChartsRequest(types: [Song.self])
                req.limit = 40
                let charts = try await withDeadline(seconds: 15) { try await req.response() }
                for chart in charts.songCharts {
                    for s in chart.items { consider(s, "Popular now"); if found.count >= 30 { break } }
                    if found.count >= 30 { break }
                }
            } catch { }
        }
        // Rank by what the swipes have taught us; keep a little randomness so it
        // doesn't collapse into one genre.
        found.shuffle()
        found.sort { Taste.score($0.song) > Taste.score($1.song) }
        phase = ""
    }

    static func key(_ artist: String, _ title: String) -> String {
        let primary = String(artist.split(separator: ",").first ?? "")
            .lowercased().trimmingCharacters(in: .whitespaces)
        return "\(primary)|\(Track.normTitle(title))"
    }
    /// Everything the user has already added or passed on — never offer these again.
    static var handled: Set<String> {
        Set((UserDefaults.standard.stringArray(forKey: "dacapo.added") ?? [])
          + (UserDefaults.standard.stringArray(forKey: "dacapo.passed") ?? []))
    }

    /// Adds ONE song immediately (swipe-right): library + playlist + remembered.
    @discardableResult
    func addOne(_ n: NewSong, playlistName: String = "✨ New for you") async -> Bool {
        var ok = false
        do { try await MusicLibrary.shared.add(n.song); ok = true } catch {}
        var preq = MusicLibraryRequest<Playlist>()
        preq.limit = 200
        var pl: Playlist? = try? await preq.response().items.first(where: { $0.name == playlistName })
        if pl == nil { pl = try? await MusicLibrary.shared.createPlaylist(name: playlistName, description: "Picked by Da Capo") }
        if let pl { try? await MusicLibrary.shared.add(n.song, to: pl) }
        var addedKeys = UserDefaults.standard.stringArray(forKey: "dacapo.added") ?? []
        addedKeys.append(Self.key(n.artist, n.title))
        UserDefaults.standard.set(Array(addedKeys.suffix(2000)), forKey: "dacapo.added")
        let k = Self.key(n.artist, n.title)
        found.removeAll { Self.key($0.artist, $0.title) == k }
        return ok
    }

    /// Adds the approved songs to the library and a playlist.
    func add(_ songs: [NewSong], playlistName: String = "✨ New for you") async -> Int {
        var added = 0
        var pl: Playlist?
        var preq = MusicLibraryRequest<Playlist>()
        preq.limit = 200
        if let existing = try? await preq.response().items.first(where: { $0.name == playlistName }) {
            if (try? await MusicLibrary.shared.edit(existing, items: [] as [Song])) != nil { pl = existing }
        }
        if pl == nil { pl = try? await MusicLibrary.shared.createPlaylist(name: playlistName, description: "Picked by Da Capo from your Apple Music recommendations") }
        var addedKeys = UserDefaults.standard.stringArray(forKey: "dacapo.added") ?? []
        for n in songs {
            do { try await MusicLibrary.shared.add(n.song); added += 1 } catch {}
            if let pl { try? await MusicLibrary.shared.add(n.song, to: pl) }
            // remember it regardless of add success — it was offered and accepted
            addedKeys.append(Self.key(n.artist, n.title))
        }
        UserDefaults.standard.set(Array(addedKeys.suffix(2000)), forKey: "dacapo.added")
        // drop them from the current in-memory pool too, so a second round in the
        // same session doesn't re-offer them before the next scan
        let justAdded = Set(songs.map { Self.key($0.artist, $0.title) })
        found.removeAll { justAdded.contains(Self.key($0.artist, $0.title)) }
        return added
    }
}
