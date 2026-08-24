import Foundation

#if targetEnvironment(simulator)
// Simulator has no Apple Music account: seed a believable library so every screen renders.
// Also the source of App Store screenshot data.
extension LibraryModel {
    func seedDemo() {
        var r = Report()
        r.total = 9412; r.artists = 1204; r.totalMinutes = 36240
        r.inNoPlaylist = 1847; r.neverPlayed = 2310; r.forgotten = 247; r.duplicates = 312
        r.oldestAdd = Calendar.current.date(byAdding: .year, value: -9, to: .now)
        r.genres = [.init(name: "Rock", count: 2918), .init(name: "Hip-Hop", count: 2071), .init(name: "Electronic", count: 1318), .init(name: "Pop", count: 1035), .init(name: "Indie", count: 847)]
        r.decades = [.init(name: "70s", count: 512), .init(name: "80s", count: 743), .init(name: "90s", count: 1420), .init(name: "00s", count: 2251), .init(name: "10s", count: 3110), .init(name: "20s", count: 1376)]
        r.topArtists = [.init(name: "Arctic Monkeys", count: 84), .init(name: "Kendrick Lamar", count: 61), .init(name: "Radiohead", count: 57), .init(name: "Dire Straits", count: 44), .init(name: "Billie Eilish", count: 39)]
        r.topSongs = [.init(name: "Do I Wanna Know? — Arctic Monkeys", count: 147), .init(name: "Weird Fishes — Radiohead", count: 121), .init(name: "Money Trees — Kendrick Lamar", count: 104), .init(name: "Sultans of Swing — Dire Straits", count: 96), .init(name: "bad guy — Billie Eilish", count: 88)]
        r.dupeExamples = [
            .init(title: "Creep", artist: "Radiohead", albumA: "Pablo Honey", albumB: "OK Computer OKNOTOK 1997 2017"),
            .init(title: "Sultans of Swing", artist: "Dire Straits", albumA: "Dire Straits", albumB: "Money for Nothing (Remastered)"),
            .init(title: "Do I Wanna Know?", artist: "Arctic Monkeys", albumA: "AM", albumB: "Live at the Royal Albert Hall"),
            .init(title: "HUMBLE.", artist: "Kendrick Lamar", albumA: "DAMN.", albumB: "DAMN. COLLECTORS EDITION."),
        ]
        r.scannedAt = .now
        report = r
        personality = "Nine years of rock devotion, gently interrupted by 2 a.m. Kendrick phases."
        delta = Delta(songs: 12, duplicates: 2, unfiled: -3, healthFrom: 61, healthTo: 64, since: Calendar.current.date(byAdding: .day, value: -8, to: .now)!)
        buckets = [
            Bucket(name: "Rock", emoji: "🎸", tracks: [], kind: .genre),
            Bucket(name: "Hip-Hop", emoji: "🎤", tracks: [], kind: .genre),
            Bucket(name: "90s", emoji: "📼", tracks: [], kind: .decade),
            Bucket(name: "Real Favorites", emoji: "❤️", tracks: [], kind: .favorites),
            Bucket(name: "Rediscover", emoji: "💎", tracks: [], kind: .rediscover),
            Bucket(name: "Review & Delete", emoji: "🗑️", tracks: [], kind: .duplicates),
        ]
        created = [CreatedPlaylist(name: "⚡ Workout", count: 214, date: Calendar.current.date(byAdding: .day, value: -8, to: .now)!)]
        userPlaylists = [UserPlaylist(name: "gym 2022", count: 118), UserPlaylist(name: "chill vibes", count: 74), UserPlaylist(name: "roadtrip!!", count: 61), UserPlaylist(name: "old but gold", count: 33)]
        let now = Date.now
        recentPlays = [RecentPlay(title: "Do I Wanna Know?", artist: "Arctic Monkeys", when: now.addingTimeInterval(-3600)),
                       RecentPlay(title: "Money Trees", artist: "Kendrick Lamar", when: now.addingTimeInterval(-7800)),
                       RecentPlay(title: "Weird Fishes", artist: "Radiohead", when: now.addingTimeInterval(-90000)),
                       RecentPlay(title: "Sultans of Swing", artist: "Dire Straits", when: now.addingTimeInterval(-176400)),
                       RecentPlay(title: "bad guy", artist: "Billie Eilish", when: now.addingTimeInterval(-260000))]
        stage = .main
    }
}
#endif
