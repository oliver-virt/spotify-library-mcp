import Foundation
import MusicKit

/// Learns from swipes: artists and genres you keep score up, ones you skip score down.
/// Deliberately simple and inspectable — no black box, and it can be reset.
enum Taste {
    private static let artistKey = "dacapo.taste.artists"
    private static let genreKey = "dacapo.taste.genres"

    private static func load(_ key: String) -> [String: Int] {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: Int]) ?? [:]
    }
    private static func save(_ d: [String: Int], _ key: String) {
        UserDefaults.standard.set(d, forKey: key)
    }
    static var artistScores: [String: Int] { load(artistKey) }
    static var genreScores: [String: Int] { load(genreKey) }

    static func record(_ song: NewSong, liked: Bool) {
        var artists = load(artistKey)
        let a = song.artist.lowercased()
        artists[a, default: 0] += liked ? 3 : -2
        save(artists, artistKey)

        var genres = load(genreKey)
        for g in song.song.genreNames.prefix(3) {
            genres[g.lowercased(), default: 0] += liked ? 2 : -1
        }
        save(genres, genreKey)
    }

    /// Higher = more likely to land. Used to rank candidates before showing them.
    static func score(_ song: Song) -> Int {
        let artists = load(artistKey), genres = load(genreKey)
        var s = artists[song.artistName.lowercased()] ?? 0
        for g in song.genreNames.prefix(3) { s += genres[g.lowercased()] ?? 0 }
        return s
    }

    /// Artists you have passed on repeatedly — stop offering them at all.
    static var blockedArtists: Set<String> {
        Set(load(artistKey).filter { $0.value <= -4 }.keys)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: artistKey)
        UserDefaults.standard.removeObject(forKey: genreKey)
    }
}
