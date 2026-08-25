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
    @Published var fatalError: String?
    @Published var phase = ""
    @Published var current = ""
    @Published var recent: [String] = []

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
        fatalError = nil
        phase = "Checking catalog access…"

        // Preflight with a hard deadline. MusicKit can hang indefinitely when the
        // developer token can't be minted, so we race it against a timer.
        do {
            let ok = try await withDeadline(seconds: 12) {
                var probe = MusicCatalogSearchRequest(term: "radiohead", types: [Song.self])
                probe.limit = 1
                let r = try await probe.response()
                return r.songs.count
            }
            phase = "Catalog OK (\(ok) hit). Matching songs…"
        } catch is DeadlineError {
            fatalError = "Catalog search timed out. Apple's MusicKit token service usually needs a few minutes after enabling MusicKit on the App ID — try again shortly. (Also check: iPhone online, Apple Music subscription active.)"
            phase = ""
            return
        } catch {
            fatalError = "Catalog search failed: \(error) — \(error.localizedDescription)"
            phase = ""
            return
        }

        var consecutiveErrors = 0

        for (k, t) in uniq {
            defer { done += 1 }
            if doneKeys.contains(k) { continue }   // resumed: already added to library previously
            current = "\(t.title) — \(t.artist)"
            do {
                let res = try await withDeadline(seconds: 10) {
                    var req = MusicCatalogSearchRequest(term: "\(t.title) \(t.artist)", types: [Song.self])
                    req.limit = 5
                    return try await req.response()
                }
                let primary = norm(String(t.artist.split(separator: ",").first ?? ""))
                if let hit = res.songs.first(where: { norm($0.artistName).contains(primary) && !primary.isEmpty }) {
                    matched += 1
                    songByKey[k] = hit
                    recent.insert("\(hit.title) — \(hit.artistName)", at: 0)
                    if recent.count > 3 { recent.removeLast() }
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
                consecutiveErrors = 0
            } catch {
                consecutiveErrors += 1
                if consecutiveErrors >= 8 {
                    fatalError = "Search keeps failing (\(error.localizedDescription)). Stopped after \(done) — tap the chip to resume once it's fixed."
                    return
                }
                try? await Task.sleep(for: .seconds(2))
            }
            try? await Task.sleep(for: .milliseconds(280))
        }
        UserDefaults.standard.set(Array(doneKeys), forKey: "dacapo.mig.done")

        // Rebuild playlists (skip empty). Idempotent-ish: same-name playlist by us gets refreshed by existing apply logic pattern; here: create fresh only if absent.
        phase = "Rebuilding playlists…"
        for p in export.playlists where !p.tracks.isEmpty {
            current = p.name
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
        current = ""
        phase = ""
        UserDefaults.standard.set(unmatched, forKey: "dacapo.mig.unmatched")
        UserDefaults.standard.set(true, forKey: "dacapo.migrationDone")
        finished = true
    }
}


struct DeadlineError: Error {}

/// Runs `work`, throwing DeadlineError if it doesn't finish in time.
func withDeadline<T: Sendable>(seconds: Double, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T?.self) { group in
        group.addTask { try await work() }
        group.addTask { try await Task.sleep(for: .seconds(seconds)); return nil }
        guard let first = try await group.next() else { throw DeadlineError() }
        group.cancelAll()
        guard let value = first else { throw DeadlineError() }
        return value
    }
}
