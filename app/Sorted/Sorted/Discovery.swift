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

    func run(owned: Set<String>) async {
        guard !running else { return }
        running = true; defer { running = false }
        errorText = nil; found = []
        var seen = Set<String>()
        let passed = Set(UserDefaults.standard.stringArray(forKey: "dacapo.passed") ?? [])
        let alreadyAdded = Set(UserDefaults.standard.stringArray(forKey: "dacapo.added") ?? [])
        func consider(_ s: Song, _ reason: String) {
            let key = "\(s.artistName.lowercased())|\(s.title.lowercased())"
            guard !owned.contains(key), !seen.contains(key),
                  !passed.contains(key), !alreadyAdded.contains(key) else { return }
            seen.insert(key)
            found.append(NewSong(id: s.id.rawValue, title: s.title, artist: s.artistName, reason: reason, song: s))
        }
        // 1. Apple's personal recommendations for this user
        phase = "Reading your recommendations…"
        do {
            let res = try await withDeadline(seconds: 20) {
                try await MusicPersonalRecommendationsRequest().response()
            }
            for rec in res.recommendations {
                let label = rec.title ?? "Recommended for you"
                phase = "Going through \(label.lowercased())…"
                for item in rec.items.prefix(12) {
                    switch item {
                    case .album(let a):
                        if let full = try? await a.with(.tracks), let t = full.tracks?.prefix(2) {
                            for track in t { if case .song(let s) = track { consider(s, label) } }
                        }
                    case .playlist(let p):
                        if let full = try? await p.with(.tracks), let t = full.tracks?.prefix(3) {
                            for track in t { if case .song(let s) = track { consider(s, label) } }
                        }
                    case .station: break
                    @unknown default: break
                    }
                    if found.count >= 30 { break }
                }
                if !found.isEmpty { phase = "\(found.count) new so far…" }
                if found.count >= 30 { break }
            }
        } catch { errorText = "Couldn't read recommendations: \(error.localizedDescription)" }

        // 2. Top up from charts if thin
        if found.count < 15 {
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
        phase = ""
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
            addedKeys.append("\(n.artist.lowercased())|\(n.title.lowercased())")
        }
        UserDefaults.standard.set(Array(addedKeys.suffix(2000)), forKey: "dacapo.added")
        // drop them from the current in-memory pool too, so a second round in the
        // same session doesn't re-offer them before the next scan
        let justAdded = Set(songs.map { "\($0.artist.lowercased())|\($0.title.lowercased())" })
        found.removeAll { justAdded.contains("\($0.artist.lowercased())|\($0.title.lowercased())") }
        return added
    }
}
