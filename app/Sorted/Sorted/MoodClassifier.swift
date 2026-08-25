import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum Mood: String, CaseIterable {
    case workout = "Workout", focus = "Focus", chill = "Chill", party = "Party", drive = "Drive"
    var emoji: String {
        switch self { case .workout: "⚡"; case .focus: "🧠"; case .chill: "🌙"; case .party: "🪩"; case .drive: "🛣️" }
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct CapIntent {
    @Guide(description: "One of: sort, duplicates, rediscover, report, chat")
    var intent: String
    @Guide(description: "Cap's one-sentence reply, dry and warm, max 18 words")
    var reply: String
}

@available(iOS 26.0, *)
@Generable
struct ArtistMoodBatch {
    @Guide(description: "One entry per artist, same order as the input list")
    var entries: [Entry]
    @Generable
    struct Entry {
        @Guide(description: "The artist name, copied exactly from the input")
        var artist: String
        @Guide(description: "Best mood for this artist's typical music: Workout, Focus, Chill, Party, or Drive")
        var mood: String
        @Guide(description: "0-100: how well you actually know this artist. Below 50 = guessing")
        var confidence: Int
    }
}
#endif

struct MoodClassifier {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// Agentic turn: the model chooses and calls Cap's tools, then answers.
    /// Returns Cap's sentence; side effects (cards, chips) arrive via AgentBus.
    static func agentTurn(_ text: String) async -> String? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return nil }
        let session = LanguageModelSession(tools: CapAgent.tools, instructions: CapAgent.instructions)
        do {
            let r = try await session.respond(to: text)
            return r.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch { return nil }
        #else
        return nil
        #endif
    }

    /// Free-text interpreter: maps the user's sentence to one of Cap's intents + a short in-voice reply.
    /// The model NEVER does the work — it only picks the tool and writes one line.
    static func interpret(_ text: String, context: String) async -> (intent: String, reply: String)? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return nil }
        let session = LanguageModelSession(instructions: """
            You are Cap, a music librarian inside the Da Capo app. You know this user's library:
            \(context)

            Pick ONE intent for their message:
            - sort: they want their library organised into playlists
            - duplicates: doubles, copies, cleanup
            - rediscover: forgotten, old, unplayed songs to revisit
            - new: they want new music, recommendations, something to listen to
            - report: they want the full stats card (health, decades, genres, play counts)
            - chat: a QUESTION you can answer from the library facts above, or small talk

            For `chat`, ANSWER the question directly using the facts above — be specific,
            use their real artists, genres and numbers. Never say you can't help with a
            question about their own music; the facts are right there.
            Only refuse if the message has nothing to do with their music library
            (weather, jokes, other apps) — then say it is not your counter and name
            what you do.

            `reply` is ONE sentence, max 25 words, dry and warm. No emoji, no quotes.
            """)
        do {
            let r = try await session.respond(to: text, generating: CapIntent.self).content
            return (r.intent, r.reply)
        } catch { return nil }
        #else
        return nil
        #endif
    }

    /// One playful sentence describing the library. Nil if unavailable/failed.
    static func oneLiner(facts: String) async -> String? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return nil }
        let session = LanguageModelSession(instructions: "You write ONE playful, specific sentence (max 15 words) describing someone's music library from stats. Warm, a little cheeky, never mean. No emoji, no quotes.")
        return try? await session.respond(to: facts).content.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        return nil
        #endif
    }

    /// Returns artist → mood for artists the model knows with confidence ≥ 80. Unknown artists are simply absent.
    /// (Device probe 2026-08-23: the model is reliable on mainstream Latin-script artists at high confidence,
    /// and confidently wrong on niche/non-Latin ones — hence the hard gate + genre hint in the prompt.)
    static func classify(artists: [(name: String, genre: String)],
                         progress: @escaping @Sendable (Int, Int) async -> Void) async -> [String: Mood] {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return [:] }
        var out: [String: Mood] = [:]
        let batches = stride(from: 0, to: artists.count, by: 8).map { Array(artists[$0..<min($0 + 8, artists.count)]) }
        var done = 0
        for batch in batches {
            let list = batch.map { $0.genre.isEmpty ? $0.name : "\($0.name) (genre tag: \($0.genre))" }.joined(separator: "\n")
            let session = LanguageModelSession(instructions: """
                You assign music artists to ONE listening mood: Workout (high energy, gym), Focus (calm, instrumental-leaning, good for work), Chill (relaxed evening), Party (danceable, social), Drive (rock/anthemic, windows down).
                If you do not genuinely know the artist, set confidence below 50. Never guess from the name alone.
                """)
            do {
                let r = try await session.respond(to: "Artists:\n\(list)", generating: ArtistMoodBatch.self).content
                for e in r.entries where e.confidence >= 80 {
                    if let m = Mood(rawValue: e.mood),
                       let orig = batch.first(where: { $0.name.lowercased() == e.artist.lowercased() }) {
                        out[orig.name] = m
                    }
                }
            } catch { /* skip failed batch, keep going */ }
            done += batch.count
            await progress(done, artists.count)
        }
        return out
        #else
        return [:]
        #endif
    }
}
