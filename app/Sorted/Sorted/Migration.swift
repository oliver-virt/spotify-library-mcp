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
    @Published var skipped = 0

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
        var idByKey = (UserDefaults.standard.dictionary(forKey: "dacapo.mig.ids") as? [String: String]) ?? [:]
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

        // Split: already-done vs still to search. Show the resume count honestly.
        let pending = uniq.filter { !doneKeys.contains($0.key) }
        skipped = uniq.count - pending.count
        done = skipped
        matched = skipped
        if skipped > 0 { phase = "\(skipped) already matched — picking up where we left off" }

        // Search 5 at a time: ~5x faster than sequential, still polite to the API.
        let items = Array(pending)
        var consecutiveErrors = 0
        for chunkStart in stride(from: 0, to: items.count, by: 5) {
            if fatalError != nil { break }
            let chunk = Array(items[chunkStart..<min(chunkStart + 5, items.count)])
            current = chunk.first.map { "\($0.value.title) — \($0.value.artist)" } ?? ""
            let primaries = chunk.map { (k: $0.key, t: $0.value, primary: norm(String($0.value.artist.split(separator: ",").first ?? ""))) }

            let results: [(String, Song?)] = await withTaskGroup(of: (String, Song?).self) { group in
                for item in primaries {
                    group.addTask {
                        do {
                            let res = try await withDeadline(seconds: 12) {
                                var req = MusicCatalogSearchRequest(term: "\(item.t.title) \(item.t.artist)", types: [Song.self])
                                req.limit = 5
                                return try await req.response()
                            }
                            let norm: (String) -> String = { $0.lowercased().replacingOccurrences(of: #"[^\p{L}\p{N}]"#, with: "", options: .regularExpression) }
                            let hit = res.songs.first { !item.primary.isEmpty && norm($0.artistName).contains(item.primary) }
                            return (item.k, hit)
                        } catch { return (item.k, nil) }
                    }
                }
                var out: [(String, Song?)] = []
                for await r in group { out.append(r) }
                return out
            }

            var failures = 0
            for (k, hit) in results {
                done += 1
                if let hit {
                    matched += 1
                    songByKey[k] = hit
                    idByKey[k] = hit.id.rawValue
                    doneKeys.insert(k)
                    recent.insert("\(hit.title) — \(hit.artistName)", at: 0)
                    if recent.count > 3 { recent.removeLast() }
                    if likedKeys.contains(k) {
                        do { try await MusicLibrary.shared.add(hit); addedToLibrary += 1 } catch {}
                    }
                } else {
                    failures += 1
                    if let t = uniq[k] { unmatched.append("\(t.title) — \(t.artist)") }
                }
            }
            // persist after every chunk — never lose more than 5 songs of work
            UserDefaults.standard.set(Array(doneKeys), forKey: "dacapo.mig.done")
            UserDefaults.standard.set(idByKey, forKey: "dacapo.mig.ids")

            consecutiveErrors = failures == results.count ? consecutiveErrors + 1 : 0
            if consecutiveErrors >= 4 {
                fatalError = "Search kept failing. Stopped at \(done) of \(total) — tap the job again to resume."
                break
            }
            try? await Task.sleep(for: .milliseconds(120))
        }
        UserDefaults.standard.set(Array(doneKeys), forKey: "dacapo.mig.done")
        UserDefaults.standard.set(idByKey, forKey: "dacapo.mig.ids")

        // Resolve songs matched in EARLIER runs (resume): fetch by stored catalog id, batched.
        let missing = idByKey.filter { songByKey[$0.key] == nil }
        if !missing.isEmpty {
            phase = "Loading \(missing.count) songs matched earlier…"
            let entries = Array(missing)
            for chunk in stride(from: 0, to: entries.count, by: 25).map({ Array(entries[$0..<min($0+25, entries.count)]) }) {
                let ids = chunk.map { MusicItemID($0.value) }
                do {
                    let songs = try await withDeadline(seconds: 15) {
                        try await MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: ids).response()
                    }
                    for (k, v) in chunk {
                        if let song = songs.items.first(where: { $0.id.rawValue == v }) { songByKey[k] = song }
                    }
                } catch { }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }

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
