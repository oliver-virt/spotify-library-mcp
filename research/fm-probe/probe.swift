// Probe: does Apple's on-device Foundation Model know these artists well enough to classify them?
import Foundation
import FoundationModels

@Generable
struct Classification {
    @Guide(description: "Artist's country, e.g. Israel, USA, UK, Belgium, or 'unknown'")
    var country: String
    @Guide(description: "One of: rock, pop, hip-hop, electronic, psytrance, metal, indie, israeli-rock, israeli-pop, mizrahi, classic-rock, jazz, other, unknown")
    var genre: String
    @Guide(description: "Decade they became known, e.g. 1970s, 2010s, or 'unknown'")
    var era: String
    @Guide(description: "Confidence 0-100 that you actually know this artist (0 = guessing)")
    var confidence: Int
}

@main struct Probe {
    static func main() async {
        let data = try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let lists = try! JSONSerialization.jsonObject(with: data) as! [String: [String]]
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { print("MODEL UNAVAILABLE: \(model.availability)"); exit(1) }

        for (group, artists) in lists {
            print("== \(group)")
            for a in artists {
                let session = LanguageModelSession(instructions: "You classify music artists. If you do not know the artist, say genre 'unknown' and confidence under 30. Do not guess.")
                let t0 = Date()
                do {
                    let r = try await session.respond(to: "Artist: \(a)", generating: Classification.self).content
                    print(String(format: "%-22@ %-8@ %-14@ %-7@ conf=%3d  %.1fs", a, r.country, r.genre, r.era, r.confidence, Date().timeIntervalSince(t0)))
                } catch { print("\(a): ERROR \(error)") }
            }
        }

    }
}
