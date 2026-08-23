import SwiftUI
import MusicKit
import MediaPlayer

struct Track: Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let genre: String
    let playCount: Int
    let skipCount: Int
    let added: Date?
    let lastPlayed: Date?
    let song: Song
    var key: String { "\(artist.lowercased())|\(Self.normTitle(title))" }
    static func normTitle(_ t: String) -> String {
        t.lowercased()
            .replacingOccurrences(of: #"\s*[-(\[].*(live|remaster|acoustic|version|edit|mix|feat|demo).*$"#,
                                  with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}

struct Bucket: Identifiable {
    let id = UUID()
    var name: String
    var emoji: String
    var tracks: [Track]
    var enabled = true
    var kind: Kind
    enum Kind { case genre, rediscover, onRepeat, duplicates }
}

struct Report {
    var total = 0
    var artists = 0
    var genres: [(String, Int)] = []
    var topArtists: [(String, Int)] = []
    var neverPlayed = 0
    var forgotten = 0
    var duplicates = 0
    var inNoPlaylist = 0
    var oldestAdd: Date?
    var totalMinutes = 0
}

@MainActor
final class LibraryModel: ObservableObject {
    enum Stage { case welcome, scanning, report, plan, applying, done }
    @Published var stage: Stage = .welcome
    @Published var scanStatus = ""
    @Published var tracks: [Track] = []
    @Published var report = Report()
    @Published var buckets: [Bucket] = []
    @Published var applyLog: [String] = []
    @Published var errorText: String?

    func scan() async {
        stage = .scanning
        errorText = nil
        let auth = await MusicAuthorization.request()
        guard auth == .authorized else {
            errorText = "Sorted needs access to your library. Enable it in Settings → Privacy → Media & Apple Music."
            stage = .welcome; return
        }
        scanStatus = "Reading your library…"
        var meta: [String: MPMediaItem] = [:]
        var durations: [String: TimeInterval] = [:]
        for m in MPMediaQuery.songs().items ?? [] {
            let k = "\((m.artist ?? "").lowercased())|\(Track.normTitle(m.title ?? ""))"
            meta[k] = m
            durations[k] = m.playbackDuration
        }
        var inPlaylists = Set<MPMediaEntityPersistentID>()
        for pl in MPMediaQuery.playlists().collections ?? [] {
            for item in pl.items { inPlaylists.insert(item.persistentID) }
        }
        var collected: [Track] = []
        do {
            var req = MusicLibraryRequest<Song>()
            req.limit = 500
            var page = try await req.response()
            var offset = 0
            while true {
                for s in page.items {
                    let k = "\(s.artistName.lowercased())|\(Track.normTitle(s.title))"
                    let m = meta[k]
                    collected.append(Track(
                        id: s.id.rawValue, title: s.title, artist: s.artistName,
                        genre: m?.genre ?? s.genreNames.first ?? "",
                        playCount: m?.playCount ?? s.playCount ?? 0,
                        skipCount: m?.skipCount ?? 0,
                        added: m?.dateAdded ?? s.libraryAddedDate,
                        lastPlayed: m?.lastPlayedDate ?? s.lastPlayedDate,
                        song: s))
                }
                scanStatus = "Reading your library… \(collected.count) songs"
                offset += page.items.count
                if page.items.count < 500 { break }
                var next = MusicLibraryRequest<Song>()
                next.limit = 500; next.offset = offset
                page = try await next.response()
            }
        } catch {
            errorText = "Couldn't read your library: \(error.localizedDescription)"
            stage = .welcome; return
        }
        tracks = collected
        scanStatus = "Analysing…"
        computeReport(inPlaylists: inPlaylists, meta: meta, durations: durations)
        buildPlan()
        stage = .report
    }

    private func computeReport(inPlaylists: Set<MPMediaEntityPersistentID>, meta: [String: MPMediaItem], durations: [String: TimeInterval]) {
        var r = Report()
        r.total = tracks.count
        var artistCount: [String: Int] = [:], genreCount: [String: Int] = [:]
        var seen: Set<String> = []
        let yearAgo = Calendar.current.date(byAdding: .year, value: -1, to: .now)!
        var secs: TimeInterval = 0
        for t in tracks {
            artistCount[t.artist, default: 0] += 1
            let g = t.genre.isEmpty ? "Unknown" : t.genre
            genreCount[g, default: 0] += 1
            if t.playCount == 0 { r.neverPlayed += 1 }
            if let a = t.added, a < yearAgo, t.playCount <= 1 { r.forgotten += 1 }
            if seen.contains(t.key) { r.duplicates += 1 } else { seen.insert(t.key) }
            if let m = meta[t.key], !inPlaylists.contains(m.persistentID) { r.inNoPlaylist += 1 }
            secs += durations[t.key] ?? 0
            if let a = t.added, r.oldestAdd == nil || a < r.oldestAdd! { r.oldestAdd = a }
        }
        r.artists = artistCount.count
        r.topArtists = artistCount.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
        r.genres = genreCount.sorted { $0.value > $1.value }.prefix(6).map { ($0.key, $0.value) }
        r.totalMinutes = Int(secs / 60)
        report = r
    }

    private func buildPlan() {
        var out: [Bucket] = []
        var byGenre: [String: [Track]] = [:]
        for t in tracks { byGenre[t.genre.isEmpty ? "Unknown" : t.genre, default: []].append(t) }
        let big = byGenre.filter { $0.value.count >= 8 && $0.key != "Unknown" }
            .sorted { $0.value.count > $1.value.count }.prefix(6)
        let bigNames = Set(big.map(\.key))
        let emojiMap = ["rock": "🎸", "alternative": "🎛️", "pop": "✨", "hip-hop": "🎤", "hip hop": "🎤", "rap": "🎤",
                        "dance": "🪩", "electronic": "🪩", "metal": "🤘", "r&b": "🎷", "soul": "🎷", "jazz": "🎺",
                        "classical": "🎻", "country": "🤠", "indie": "🌿", "folk": "🪕", "singer": "🎙️", "world": "🌍", "soundtrack": "🎬"]
        for (g, ts) in big {
            let e = emojiMap.first { g.lowercased().contains($0.key) }?.value ?? "🎵"
            out.append(Bucket(name: g, emoji: e, tracks: ts, kind: .genre))
        }
        let rest = tracks.filter { !bigNames.contains($0.genre) }
        if rest.count >= 8 { out.append(Bucket(name: "Mixed Bag", emoji: "🎲", tracks: rest, kind: .genre)) }
        let yearAgo = Calendar.current.date(byAdding: .year, value: -1, to: .now)!
        var perArtist: [String: Int] = [:]
        var forgotten: [Track] = []
        for t in tracks.filter({ ($0.added ?? .now) < yearAgo && $0.playCount <= 1 })
            .sorted(by: { ($0.added ?? .now) < ($1.added ?? .now) }) {
            if perArtist[t.artist, default: 0] < 3 { perArtist[t.artist, default: 0] += 1; forgotten.append(t) }
        }
        if forgotten.count >= 5 { out.append(Bucket(name: "Rediscover", emoji: "💎", tracks: Array(forgotten.prefix(100)), kind: .rediscover)) }
        let hot = tracks.filter { $0.playCount > 0 }.sorted { $0.playCount > $1.playCount }.prefix(50)
        if hot.count >= 10 { out.append(Bucket(name: "On Repeat", emoji: "🔁", tracks: Array(hot), kind: .onRepeat)) }
        var seen: Set<String> = []; var dupes: [Track] = []
        for t in tracks { if seen.contains(t.key) { dupes.append(t) } else { seen.insert(t.key) } }
        if !dupes.isEmpty { out.append(Bucket(name: "Review & Delete", emoji: "🗑️", tracks: dupes, kind: .duplicates)) }
        buckets = out
    }

    func apply() async {
        stage = .applying
        applyLog = []
        for i in buckets.indices where buckets[i].enabled {
            let b = buckets[i]
            let name = "\(b.emoji) \(b.name)"
            do {
                let desc = b.kind == .duplicates
                    ? "Duplicates found by Sorted — review and delete in Music"
                    : "Organised by Sorted"
                let pl = try await MusicLibrary.shared.createPlaylist(name: name, description: desc)
                var added = 0
                for t in b.tracks {
                    do { try await MusicLibrary.shared.add(t.song, to: pl); added += 1 } catch {}
                }
                applyLog.append("✅ \(name) — \(added) songs")
            } catch {
                applyLog.append("❌ \(name) — \(error.localizedDescription)")
            }
        }
        applyLog.append("Done. Open Music to see your new playlists.")
        stage = .done
    }
}
