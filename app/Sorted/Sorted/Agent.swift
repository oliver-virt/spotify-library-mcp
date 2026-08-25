import Foundation
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Tools write their side effects here; the chat renders them after the turn.
@MainActor
final class AgentBus {
    static let shared = AgentBus()
    weak var lib: LibraryModel?
    var cards: [ChatMsg.Kind] = []
    var chips: [String] = []
    var wantsPicker = false
    func reset() { cards = []; chips = []; wantsPicker = false }
}

/// Songs and artists the user says don't represent them — excluded from stats
/// and from recommendations. (Spotify shipped this to 20M+ users for a reason.)
enum Excluded {
    private static let key = "dacapo.excluded"
    static var keys: Set<String> { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
    static func add(_ k: String) {
        var all = UserDefaults.standard.stringArray(forKey: key) ?? []
        all.append(k.lowercased())
        UserDefaults.standard.set(Array(Set(all)), forKey: key)
    }
    static func contains(artist: String, title: String) -> Bool {
        let e = keys
        return e.contains(artist.lowercased()) || e.contains("\(artist.lowercased())|\(title.lowercased())")
    }
    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
struct SortLibraryTool: Tool {
    let name = "sortLibrary"
    let description = "Propose playlists built from the user's library (genre, decade, favorites, forgotten). Use when they want their library organised, sorted, tidied or turned into playlists."
    @Generable struct Arguments {}
    func call(arguments: Arguments) async throws -> String {
        await MainActor.run {
            AgentBus.shared.cards.append(.plan)
            AgentBus.shared.chips = ["Add mood playlists", "How do I listen?"]
        }
        let n = await MainActor.run { AgentBus.shared.lib?.buckets.count ?? 0 }
        return ("Proposed \(n) playlists. The user can toggle any off and approve.")
    }
}

@available(iOS 26.0, *)
struct FindDuplicatesTool: Tool {
    let name = "findDuplicates"
    let description = "Find songs that appear twice in the library from different releases. Use for anything about duplicates, doubles or copies."
    @Generable struct Arguments {}
    func call(arguments: Arguments) async throws -> String {
        let count = await MainActor.run { AgentBus.shared.lib?.report.duplicates ?? 0 }
        if count > 0 { await MainActor.run { AgentBus.shared.cards.append(.dupes) } }
        return (count > 0 ? "Found \(count) duplicates; showing examples." : "No duplicates found.")
    }
}

@available(iOS 26.0, *)
struct RediscoverTool: Tool {
    let name = "rediscoverForgotten"
    let description = "Surface songs the user saved long ago and never played since. Use for forgotten, old, unplayed or 'what did I miss' requests."
    @Generable struct Arguments {}
    func call(arguments: Arguments) async throws -> String {
        let tracks = await MainActor.run { AgentBus.shared.lib?.rediscoverList() ?? [] }
        if tracks.isEmpty { return ("Nothing forgotten yet.") }
        await MainActor.run {
            AgentBus.shared.cards.append(.rediscover(Array(tracks.prefix(6))))
            AgentBus.shared.chips = ["Make it a playlist", "Sort my library"]
        }
        return ("Found \(tracks.count) forgotten songs; showing six.")
    }
}

@available(iOS 26.0, *)
struct LibraryReportTool: Tool {
    let name = "libraryReport"
    let description = "Show the full stats card: play counts Apple hides, genres, decades, health score. Use when they ask about their stats, taste, listening or want the report."
    @Generable struct Arguments {}
    func call(arguments: Arguments) async throws -> String {
        await MainActor.run { AgentBus.shared.cards.append(.report) }
        let r = await MainActor.run { AgentBus.shared.lib?.report }
        guard let r else { return ("No library scanned yet.") }
        return ("Showed the report: \(r.total) songs, health \(r.health)/100.")
    }
}

@available(iOS 26.0, *)
struct FindNewMusicTool: Tool {
    let name = "findNewMusic"
    let description = "Look for music the user does not own yet, from artists they like and similar artists. Use whenever they want recommendations, new music, or something to listen to."
    @Generable struct Arguments {}
    func call(arguments: Arguments) async throws -> String {
        await MainActor.run { AgentBus.shared.wantsPicker = true }
        return ("Opened the picker so they can choose what kind of new music.")
    }
}

@available(iOS 26.0, *)
struct ExcludeFromTasteTool: Tool {
    let name = "excludeFromTaste"
    let description = "Exclude an artist or song from the user's stats and recommendations, for music that isn't really theirs — background noise, something left playing, a kid's song, a track they don't actually like."
    @Generable struct Arguments {
        @Guide(description: "The artist name, or the song title, exactly as the user said it")
        var subject: String
    }
    func call(arguments: Arguments) async throws -> String {
        Excluded.add(arguments.subject)
        await MainActor.run { AgentBus.shared.lib?.applyExclusions() }
        return ("Excluded \(arguments.subject) from stats and recommendations.")
    }
}

@available(iOS 26.0, *)
struct LibraryFactsTool: Tool {
    let name = "libraryFacts"
    let description = "Get the current numbers about this user's library — totals, top artists, genres, decades, most played songs. Use before answering any question about their music."
    @Generable struct Arguments {}
    func call(arguments: Arguments) async throws -> String {
        let text = await MainActor.run { AgentBus.shared.lib?.factsForAgent() ?? "No library scanned yet." }
        return (text)
    }
}

@available(iOS 26.0, *)
enum CapAgent {
    static var tools: [any Tool] {
        [LibraryFactsTool(), SortLibraryTool(), FindDuplicatesTool(), RediscoverTool(),
         LibraryReportTool(), FindNewMusicTool(), ExcludeFromTasteTool()]
    }
    static let instructions = """
    You are Cap, a music librarian inside the Da Capo app. You look after the user's
    Apple Music library and you can act on it with your tools.

    Rules:
    - If the user asks you to DO something (organise, clean, find new music, show stats,
      exclude something), call the matching tool. Do not describe what you would do.
    - If they ask a QUESTION about their music, call libraryFacts first and answer from
      the real numbers — never guess, never give generic music advice.
    - You can call more than one tool when it helps.
    - Only decline when the request has nothing to do with their music library.
    - Reply in ONE sentence, max 25 words, dry and warm. No emoji. Never list your tools.
    """
}
#endif
