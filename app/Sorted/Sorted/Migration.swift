import Foundation
import MusicKit

// Spotify → Apple Music migration. Bundled export → catalog search (artist-verified) →
// add to library + rebuild playlists. Resumable; throttled; unmatched reported.

struct SpotifyExport: Codable {
    struct T: Codable { let title: String; let artist: String }
    struct P: Codable { let name: String; let tracks: [T] }
    let exported: String
    let liked: [T]
    let playlists: [P]
}

@MainActor
final class Migration: ObservableObject {
    @Published var running = false
    @Published var done = 0
    @Published var total = 0
    @Published var matched = 0
    @Published var addedToLibrary = 0
    @Published var playlistsBuilt = 0
    @Published var unmatched: [String] = []
    @Published var finished = UserDefaults.standard.bool(forKey: "dacapo.migrationDone")

    static var exportAvailable: Bool {
        Bundle.main.url(forResource: "spotify-export", withExtension: "json") != nil
    }

    private func norm(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: #"[^\p{L}\p{N}]"#, with: "", options: .regularExpression)
    }
    private func key(_ t: SpotifyExport.T) -> String { norm(t.artist) + "|" + norm(t.title) }

    func run() async {
        guard !running,
              let url = Bundle.main.url(forResource: "spotify-export", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let export = try? JSONDecoder().decode(SpotifyExport.self, from: data) else { return }
        running = true
        defer { running = false }

        // Unique tracks across liked + playlists
        var uniq: [String: SpotifyExport.T] = [:]
        for t in export.liked { uniq[key(t)] = t }
        for p in export.playlists { for t in p.tracks { uniq[key(t)] = t } }
        let likedKeys = Set(export.liked.map(key))
        total = uniq.count
        done = 0; matched = 0; addedToLibrary = 0; unmatched = []

        var doneKeys = Set(UserDefaults.standard.stringArray(forKey: "dacapo.mig.done") ?? [])
        var songByKey: [String: Song] = [:]

        for (k, t) in uniq {
            defer { done += 1 }
            if doneKeys.contains(k) { continue }   // resumed: already added to library previously
            do {
                var req = MusicCatalogSearchRequest(term: "\(t.title) \(t.artist)", types: [Song.self])
                req.limit = 5
                let res = try await req.response()
                let primary = norm(String(t.artist.split(separator: ",").first ?? ""))
                if let hit = res.songs.first(where: { norm($0.artistName).contains(primary) && !primary.isEmpty }) {
                    matched += 1
                    songByKey[k] = hit
                    if likedKeys.contains(k) {
                        do { try await MusicLibrary.shared.add(hit); addedToLibrary += 1 } catch {}
                    }
                    doneKeys.insert(k)
                    if doneKeys.count % 25 == 0 {
                        UserDefaults.standard.set(Array(doneKeys), forKey: "dacapo.mig.done")
                    }
                } else {
                    unmatched.append("\(t.title) — \(t.artist)")
                }
            } catch {
                // transient network/rate error: brief backoff, keep going
                try? await Task.sleep(for: .seconds(2))
            }
            try? await Task.sleep(for: .milliseconds(280))
        }
        UserDefaults.standard.set(Array(doneKeys), forKey: "dacapo.mig.done")

        // Rebuild playlists (skip empty). Idempotent-ish: same-name playlist by us gets refreshed by existing apply logic pattern; here: create fresh only if absent.
        for p in export.playlists where !p.tracks.isEmpty {
            let songs = p.tracks.compactMap { songByKey[key($0)] }
            guard !songs.isEmpty else { continue }
            do {
                var preq = MusicLibraryRequest<Playlist>()
                preq.limit = 200
                let existing = (try? await preq.response().items.first { $0.name == p.name }) ?? nil
                var pl: Playlist
                if let ex = existing {
                    do { _ = try await MusicLibrary.shared.edit(ex, items: [] as [Song]); pl = ex }
                    catch { continue }  // foreign same-name: skip
                } else {
                    pl = try await MusicLibrary.shared.createPlaylist(name: p.name, description: "Imported from Spotify by Da Capo")
                }
                for s in songs { try? await MusicLibrary.shared.add(s, to: pl) }
                playlistsBuilt += 1
            } catch { continue }
        }
        UserDefaults.standard.set(unmatched, forKey: "dacapo.mig.unmatched")
        UserDefaults.standard.set(true, forKey: "dacapo.migrationDone")
        finished = true
    }
}
