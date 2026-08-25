import SwiftUI
import MusicKit
import MediaPlayer

struct Track: Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let genre: String
    let album: String
    let playCount: Int
    let skipCount: Int
    let added: Date?
    let lastPlayed: Date?
    let year: Int
    let seconds: Double
    let downloaded: Bool
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
    var countOverride: Int? = nil
    var displayCount: Int { countOverride ?? tracks.count }
    enum Kind { case genre, mood, decade, favorites, rediscover, onRepeat, duplicates }
}

struct Pair: Codable, Hashable { let name: String; let count: Int }

struct Report: Codable {
    var total = 0
    var artists = 0
    var genres: [Pair] = []
    var decades: [Pair] = []
    var topArtists: [Pair] = []
    var topSongs: [Pair] = []
    var neverPlayed = 0
    var forgotten = 0
    var duplicates = 0
    var inNoPlaylist = 0
    var oldestAdd: Date?
    var totalMinutes = 0
    var scannedAt = Date.distantPast
    var dupeExamples: [DupeExample] = []
    var dupeDownloadedCount = 0
    var dupeSeconds: Double = 0

    /// 0–100: how organised the library is. Filed 40%, dedup 30%, actually-played 30%.
    var health: Int {
        guard total > 0 else { return 0 }
        let filed = 1 - Double(inNoPlaylist) / Double(total)
        let dedup = 1 - Double(duplicates) / Double(total)
        let played = 1 - Double(neverPlayed) / Double(total)
        return Int((0.4 * filed + 0.3 * dedup + 0.3 * played) * 100)
    }
    /// Health if the user applies the plan: everything filed, duplicates handled.
    var projectedHealth: Int {
        guard total > 0 else { return 0 }
        let played = 1 - Double(neverPlayed) / Double(total)
        return Int((0.4 + 0.3 + 0.3 * played) * 100)
    }
    static func load() -> Report? {
        guard let d = UserDefaults.standard.data(forKey: "dacapo.report") else { return nil }
        return try? JSONDecoder().decode(Report.self, from: d)
    }
    func save() { UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: "dacapo.report") }
}

struct DupeExample: Codable, Hashable, Identifiable {
    var id: String { "\(artist)|\(title)|\(albumA)|\(albumB)" }
    let title: String, artist: String, albumA: String, albumB: String
}

struct UserPlaylist: Identifiable {
    var id: String { name }
    let name: String
    let count: Int
}

struct RecentPlay: Identifiable {
    var id: String { title + artist }
    let title: String, artist: String, when: Date
}

struct Delta {
    let songs: Int, duplicates: Int, unfiled: Int, healthFrom: Int, healthTo: Int, since: Date
    var isEmpty: Bool { songs == 0 && duplicates == 0 && unfiled == 0 && healthFrom == healthTo }
}

@MainActor
final class LibraryModel: ObservableObject {
    enum Stage { case welcome, scanning, main }
    @Published var stage: Stage = .welcome
    @Published var scanStatus = ""
    @Published var tracks: [Track] = []
    @Published var report = Report()
    @Published var delta: Delta?
    let migration = Migration()
    let discovery = Discovery()
    @Published var userPlaylists: [UserPlaylist] = []
    @Published var recentPlays: [RecentPlay] = []

    init() {
        if let saved = Report.load() { report = saved; stage = .main }
    }
    @Published var buckets: [Bucket] = []
    @Published var applyLog: [String] = []
    @Published var applying = false
    @Published var errorText: String?
    @Published var created: [CreatedPlaylist] = CreatedPlaylist.load()
    @Published var moodProgress: (done: Int, total: Int)?
    @Published var moodsAdded = false
    @Published var personality: String?

    func scan() async {
        let silent = stage == .main            // returning user: keep showing the cached card
        if !silent { stage = .scanning }
        errorText = nil
        let auth = await MusicAuthorization.request()
        guard auth == .authorized else {
            errorText = "Da Capo needs access to your library. Enable it in Settings → Privacy → Media & Apple Music."
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
        var pls: [UserPlaylist] = []
        for pl in MPMediaQuery.playlists().collections ?? [] {
            for item in pl.items { inPlaylists.insert(item.persistentID) }
            if let mp = pl as? MPMediaPlaylist, let name = mp.name, !name.isEmpty {
                pls.append(UserPlaylist(name: name, count: pl.count))
            }
        }
        userPlaylists = pls.sorted { $0.count > $1.count }
        recentPlays = (MPMediaQuery.songs().items ?? [])
            .compactMap { m -> RecentPlay? in
                guard let d = m.lastPlayedDate else { return nil }
                return RecentPlay(title: m.title ?? "?", artist: m.artist ?? "", when: d)
            }
            .sorted { $0.when > $1.when }
            .prefix(8).map { $0 }
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
                        album: s.albumTitle ?? "",
                        playCount: m?.playCount ?? s.playCount ?? 0,
                        skipCount: m?.skipCount ?? 0,
                        added: m?.dateAdded ?? s.libraryAddedDate,
                        lastPlayed: m?.lastPlayedDate ?? s.lastPlayedDate,
                        year: (m?.releaseDate).map { Calendar.current.component(.year, from: $0) }
                              ?? (s.releaseDate).map { Calendar.current.component(.year, from: $0) } ?? 0,
                        seconds: m?.playbackDuration ?? s.duration ?? 0,
                        downloaded: m.map { !$0.isCloudItem } ?? false,
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
        let previous = report.scannedAt > .distantPast ? report : nil
        computeReport(inPlaylists: inPlaylists, meta: meta, durations: durations)
        report.scannedAt = .now
        report.save()
        if let p = previous {
            let d = Delta(songs: report.total - p.total, duplicates: report.duplicates - p.duplicates,
                          unfiled: report.inNoPlaylist - p.inNoPlaylist, healthFrom: p.health, healthTo: report.health,
                          since: p.scannedAt)
            delta = d.isEmpty ? nil : d
        }
        buildPlan()
        stage = .main
    }

    func makePersonality() async {
        guard MoodClassifier.isAvailable, personality == nil else { return }
        let g = report.genres.prefix(3).map { "\($0.name) \(Int(round(Double($0.count) * 100 / Double(max(report.total, 1)))))%" }.joined(separator: ", ")
        let facts = "Top artist: \(report.topArtists.first?.name ?? "?") (\(report.topArtists.first?.count ?? 0) songs). Genres: \(g). \(report.neverPlayed) of \(report.total) never played. Decades: \(report.decades.map { "\($0.name):\($0.count)" }.joined(separator: " "))."
        personality = await MoodClassifier.oneLiner(facts: facts)
    }

    private func computeReport(inPlaylists: Set<MPMediaEntityPersistentID>, meta: [String: MPMediaItem], durations: [String: TimeInterval]) {
        var r = Report()
        r.total = tracks.count
        var artistCount: [String: Int] = [:], genreCount: [String: Int] = [:]
        var seen: [String: Track] = [:]
        let yearAgo = Calendar.current.date(byAdding: .year, value: -1, to: .now)!
        var secs: TimeInterval = 0
        var examples: [DupeExample] = []
        for t in tracks {
            artistCount[t.artist, default: 0] += 1
            let g = t.genre.isEmpty ? "Unknown" : t.genre
            genreCount[g, default: 0] += 1
            if t.playCount == 0 { r.neverPlayed += 1 }
            if let a = t.added, a < yearAgo, t.playCount <= 1 { r.forgotten += 1 }
            if let first = seen[t.key] {
                r.duplicates += 1
                if t.downloaded { r.dupeDownloadedCount += 1; r.dupeSeconds += t.seconds }
                if examples.count < 30 {
                    examples.append(DupeExample(title: t.title, artist: t.artist,
                        albumA: first.album.isEmpty ? "your library" : first.album,
                        albumB: t.album.isEmpty ? "another release" : t.album))
                }
            } else { seen[t.key] = t }
            if let m = meta[t.key], !inPlaylists.contains(m.persistentID) { r.inNoPlaylist += 1 }
            secs += durations[t.key] ?? 0
            if let a = t.added, r.oldestAdd == nil || a < r.oldestAdd! { r.oldestAdd = a }
        }
        var decadeCount: [Int: Int] = [:]
        for t in tracks where t.year >= 1950 { decadeCount[(t.year / 10) * 10, default: 0] += 1 }
        r.decades = decadeCount.sorted { $0.key < $1.key }.map { Pair(name: "\($0.key % 100)s", count: $0.value) }
        r.artists = artistCount.count
        r.topArtists = artistCount.sorted { $0.value > $1.value }.prefix(5).map { Pair(name: $0.key, count: $0.value) }
        r.topSongs = tracks.filter { $0.playCount > 0 }.sorted { $0.playCount > $1.playCount }.prefix(5)
            .map { Pair(name: "\($0.title) — \($0.artist)", count: $0.playCount) }
        r.genres = genreCount.sorted { $0.value > $1.value }.prefix(6).map { Pair(name: $0.key, count: $0.value) }
        r.totalMinutes = Int(secs / 60)
        r.dupeExamples = examples
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
        // Decades: iTunes used to auto-create these; Apple removed them. ≥12 songs per decade.
        var byDecade: [Int: [Track]] = [:]
        for t in tracks where t.year >= 1950 { byDecade[(t.year / 10) * 10, default: []].append(t) }
        for (d, ts) in byDecade.sorted(by: { $0.key < $1.key }) where ts.count >= 12 {
            out.append(Bucket(name: "\(d % 100)s", emoji: "📼", tracks: ts, kind: .decade))
        }
        // Real Favorites: the songs the play data says you love (favorites-as-junk-drawer fix)
        let loved = tracks.filter { $0.playCount >= 5 && $0.skipCount <= $0.playCount / 3 }
            .sorted { $0.playCount > $1.playCount }.prefix(75)
        if loved.count >= 10 { out.append(Bucket(name: "Real Favorites", emoji: "❤️", tracks: Array(loved), kind: .favorites)) }
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

    func addMoodBuckets() async {
        guard !moodsAdded else { return }
        // one entry per artist, dominant genre as hint
        var genreByArtist: [String: [String: Int]] = [:]
        for t in tracks { genreByArtist[t.artist, default: [:]][t.genre, default: 0] += 1 }
        let artists = genreByArtist.map { (name: $0.key, genre: $0.value.max { $0.value < $1.value }?.key ?? "") }
        moodProgress = (0, artists.count)
        let map = await MoodClassifier.classify(artists: artists) { [weak self] done, total in
            await MainActor.run { self?.moodProgress = (done, total) }
        }
        var byMood: [Mood: [Track]] = [:]
        for t in tracks { if let m = map[t.artist] { byMood[m, default: []].append(t) } }
        var newBuckets: [Bucket] = []
        for (mood, ts) in byMood.sorted(by: { $0.value.count > $1.value.count }) where ts.count >= 5 {
            newBuckets.append(Bucket(name: mood.rawValue, emoji: mood.emoji, tracks: ts, kind: .mood))
        }
        let insertAt = buckets.firstIndex { $0.kind != .genre && $0.kind != .mood } ?? buckets.endIndex
        buckets.insert(contentsOf: newBuckets, at: insertAt)
        moodProgress = nil
        moodsAdded = true
    }

    /// artist|title keys of everything already in the library — used to filter recommendations.
    /// Artists ranked by how much of them the user owns — the seed for discovery.
    func topOwnedArtists() -> [String] {
        var counts: [String: Int] = [:]
        for t in tracks { counts[t.artist.split(separator: ",").first.map(String.init) ?? t.artist, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }.map(\.key)
    }

    func ownedKeys() -> Set<String> {
        Set(tracks.map { Discovery.key($0.artist, $0.title) })
    }

    func rediscoverList() -> [Track] {
        let yearAgo = Calendar.current.date(byAdding: .year, value: -1, to: .now)!
        var perArtist: [String: Int] = [:]
        var out: [Track] = []
        for t in tracks.filter({ ($0.added ?? .now) < yearAgo && $0.playCount <= 1 })
            .sorted(by: { ($0.added ?? .now) < ($1.added ?? .now) }) {
            if perArtist[t.artist, default: 0] < 3 { perArtist[t.artist, default: 0] += 1; out.append(t) }
        }
        return out
    }

    func applyRediscoverOnly() async {
        let saved = buckets
        buckets = buckets.filter { $0.kind == .rediscover }
        if buckets.isEmpty {
            let r = rediscoverList()
            if !r.isEmpty { buckets = [Bucket(name: "Rediscover", emoji: "💎", tracks: Array(r.prefix(100)), kind: .rediscover)] }
        }
        await apply()
        buckets = saved.filter { b in b.kind != .rediscover }
    }

    func apply() async {
        applying = true
        applyLog = []
        var doneIdx: [UUID] = []
        for i in buckets.indices where buckets[i].enabled {
            let b = buckets[i]
            let name = "\(b.emoji) \(b.name)"
            do {
                let desc = b.kind == .duplicates
                    ? "Duplicates found by Da Capo — review and delete in Music"
                    : "Organised by Da Capo"
                // Idempotent: refresh our own playlist if it already exists; never create a twin.
                var existing: Playlist? = nil
                var preq = MusicLibraryRequest<Playlist>()
                preq.limit = 200
                if let all = try? await preq.response().items { existing = all.first { $0.name == name } }
                var pl: Playlist
                var refreshed = false
                if let ex = existing {
                    do {
                        _ = try await MusicLibrary.shared.edit(ex, items: [] as [Song])   // empty it → we own it
                        pl = ex; refreshed = true
                    } catch {
                        applyLog.append("⏭️ \(name) exists but wasn't made by Da Capo — skipped. Delete the old one in Music and re-run.")
                        continue
                    }
                } else {
                    pl = try await MusicLibrary.shared.createPlaylist(name: name, description: desc)
                }
                var added = 0
                for t in b.tracks {
                    do { try await MusicLibrary.shared.add(t.song, to: pl); added += 1 } catch {}
                }
                applyLog.append("\(refreshed ? "🔄" : "✅") \(name) — \(added) songs\(refreshed ? " (refreshed)" : "")")
                created.removeAll { $0.name == name }
                created.insert(CreatedPlaylist(name: name, count: added, date: .now), at: 0)
                doneIdx.append(b.id)
            } catch {
                applyLog.append("❌ \(name) — \(error.localizedDescription)")
            }
        }
        CreatedPlaylist.save(created)
        buckets.removeAll { doneIdx.contains($0.id) }
        applying = false
    }
}

struct CreatedPlaylist: Identifiable, Codable {
    var id = UUID()
    let name: String
    let count: Int
    let date: Date
    static func load() -> [CreatedPlaylist] {
        guard let d = UserDefaults.standard.data(forKey: "dacapo.created") else { return [] }
        return (try? JSONDecoder().decode([CreatedPlaylist].self, from: d)) ?? []
    }
    static func save(_ list: [CreatedPlaylist]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: "dacapo.created")
    }
}
