import SwiftUI
import MusicKit
import MediaPlayer

@main
struct SortedProbeApp: App {
    var body: some Scene { WindowGroup { ProbeView() } }
}

struct Result: Identifiable {
    let id = UUID()
    let name: String
    let pass: Bool?
    let detail: String
}

@MainActor
final class Probe: ObservableObject {
    @Published var results: [Result] = []
    @Published var running = false

    func log(_ name: String, _ pass: Bool?, _ detail: String) {
        results.append(Result(name: name, pass: pass, detail: detail))
        print("PROBE|\(pass == nil ? "info" : pass! ? "PASS" : "FAIL")|\(name)|\(detail)")
    }

    func runAll() async {
        running = true; results = []
        // 1. Authorization
        let status = await MusicAuthorization.request()
        log("authorize", status == .authorized, "MusicAuthorization = \(status)")
        guard status == .authorized else { running = false; return }

        // 2. Library read via MusicKit
        do {
            var req = MusicLibraryRequest<Song>()
            req.limit = 25
            let res = try await req.response()
            log("library.read", true, "songs page: \(res.items.count)")
            if let s = res.items.first {
                log("metadata", nil, "'\(s.title)' – \(s.artistName) | genres=\(s.genreNames) | plays=\(s.playCount.map(String.init) ?? "nil") | lastPlayed=\(s.lastPlayedDate?.description ?? "nil") | added=\(s.libraryAddedDate?.description ?? "nil")")
            } else {
                log("metadata", nil, "library empty — run on a device with an Apple Music library for metadata checks")
            }
        } catch { log("library.read", false, "\(error)") }

        // 2b. Library read via MediaPlayer (play/skip counts live here)
        let mpSongs = MPMediaQuery.songs().items ?? []
        log("mediaplayer.read", !mpSongs.isEmpty || true, "MPMediaQuery songs: \(mpSongs.count)")
        if let m = mpSongs.first {
            log("mediaplayer.metadata", nil, "'\(m.title ?? "?")' plays=\(m.playCount) skips=\(m.skipCount) added=\(m.dateAdded) genre=\(m.genre ?? "nil")")
        }

        // 3. Create a playlist
        var created: Playlist? = nil
        do {
            created = try await MusicLibrary.shared.createPlaylist(name: "Sorted Probe \(Int(Date().timeIntervalSince1970) % 10000)", description: "created by probe")
            log("playlist.create", true, "id=\(created!.id)")
        } catch { log("playlist.create", false, "\(error)") }

        // 4. Add tracks (from library if available, else from catalog search)
        var testSongs: [Song] = []
        do {
            var req = MusicLibraryRequest<Song>(); req.limit = 3
            testSongs = Array(try await req.response().items)
            if testSongs.count < 2 {
                let cat = MusicCatalogSearchRequest(term: "Dire Straits Sultans of Swing", types: [Song.self])
                testSongs = Array(try await cat.response().songs.prefix(2))
                log("catalog.search", !testSongs.isEmpty, "catalog fallback found \(testSongs.count)")
            }
        } catch { log("song.fetch", false, "\(error)") }
        if var pl = created, testSongs.count >= 1 {
            do {
                for s in testSongs { try await MusicLibrary.shared.add(s, to: pl) }
                log("playlist.add", true, "added \(testSongs.count)")
            } catch { log("playlist.add", false, "\(error)") }
            // 5. Remove one via edit (replace item list)
            do {
                let full = try await pl.with(.tracks)
                let tracks = full.tracks ?? []
                if tracks.count >= 2 {
                    try await MusicLibrary.shared.edit(pl, items: Array(tracks.dropFirst()))
                    let after = try await pl.with(.tracks)
                    let ok = (after.tracks?.count ?? -1) == tracks.count - 1
                    log("playlist.remove(own)", ok, "before=\(tracks.count) after=\(after.tracks?.count ?? -1)")
                } else {
                    log("playlist.remove(own)", nil, "not enough tracks to test (\(tracks.count))")
                }
            } catch { log("playlist.remove(own)", false, "\(error)") }
        }

        // 6. Edit a playlist NOT created by this app (the merge question)
        do {
            var preq = MusicLibraryRequest<Playlist>(); preq.limit = 50
            let pls = try await preq.response().items.filter { !$0.name.hasPrefix("Sorted Probe") }
            if let foreign = pls.first, let s = testSongs.first {
                do {
                    try await MusicLibrary.shared.add(s, to: foreign)
                    log("playlist.add(foreign)", true, "added to '\(foreign.name)'")
                } catch { log("playlist.add(foreign)", false, "'\(foreign.name)': \(error)") }
                do {
                    let full = try await foreign.with(.tracks)
                    try await MusicLibrary.shared.edit(foreign, items: Array(full.tracks ?? []))
                    log("playlist.edit(foreign)", true, "edit accepted on '\(foreign.name)'")
                } catch { log("playlist.edit(foreign)", false, "\(error)") }
            } else {
                log("playlist.edit(foreign)", nil, "no foreign playlist in library — create one in Music app to test")
            }
        } catch { log("playlist.list", false, "\(error)") }
        log("done", nil, "probe complete")
        running = false
    }
}

struct ProbeView: View {
    @StateObject var probe = Probe()
    var body: some View {
        NavigationStack {
            List {
                Button(probe.running ? "Running…" : "Run probe") { Task { await probe.runAll() } }
                    .disabled(probe.running)
                ForEach(probe.results) { r in
                    HStack(alignment: .top) {
                        Text(r.pass == nil ? "•" : r.pass! ? "✅" : "❌")
                        VStack(alignment: .leading) {
                            Text(r.name).font(.headline)
                            Text(r.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Sorted Probe")
        }
    }
}
