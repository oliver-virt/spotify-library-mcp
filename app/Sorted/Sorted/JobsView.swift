import SwiftUI

/// Every job Cap can do, visible — not hidden behind the chat box.
struct JobsView: View {
    @EnvironmentObject var lib: LibraryModel
    @EnvironmentObject var router: Router

    struct Job: Identifiable {
        let id: String
        let title: String
        let blurb: String
        let icon: String
        let stat: String?
        let intent: String
    }

    var jobs: [Job] {
        let r = lib.report
        return [
            Job(id: "sort", title: "Sort my library",
                blurb: "Playlists by genre, decade, real favorites — from the music you already have.",
                icon: "square.grid.2x2", stat: r.total > 0 ? "\(r.total.formatted()) songs" : nil,
                intent: "Sort my library"),
            Job(id: "new", title: "Find me something new",
                blurb: "Your Apple Music recommendations, minus everything you already own. You approve what comes in.",
                icon: "sparkles", stat: nil, intent: "Find me something new"),
            Job(id: "dupes", title: "Find duplicates",
                blurb: "Same song, different releases. Gathered into one playlist so you can clear them in a minute.",
                icon: "doc.on.doc",
                stat: r.duplicates > 0 ? (r.dupeStorageText.map { "\(r.duplicates) · \($0)" } ?? "\(r.duplicates) found") : nil,
                intent: "Find duplicates"),
            Job(id: "forgot", title: "What did I forget?",
                blurb: "Songs you saved and never came back to, with the dates to prove it.",
                icon: "clock.arrow.circlepath", stat: r.forgotten > 0 ? "\(r.forgotten) waiting" : nil,
                intent: "What did I forget?"),
            Job(id: "report", title: "How do I actually listen?",
                blurb: "Play counts Apple hides on iPhone, genres, decades, library health.",
                icon: "chart.bar", stat: r.total > 0 ? "health \(r.health)/100" : nil,
                intent: "How do I listen?"),
            Job(id: "import", title: "Import from Spotify",
                blurb: "Bring your liked songs and playlists across, matched track by track.",
                icon: "arrow.down.circle", stat: nil, intent: "Import my Spotify"),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ask for any of these, or tap.")
                        .font(.system(size: 14)).foregroundStyle(CapTheme.mute)
                        .padding(.horizontal, 16).padding(.top, 4)
                    ForEach(jobs) { job in
                        Button { Haptics.medium(); router.run(job.intent) } label: {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: job.icon)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(CapTheme.red)
                                    .frame(width: 34, height: 34)
                                    .background(RoundedRectangle(cornerRadius: 9).fill(CapTheme.red.opacity(0.12)))
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(job.title).font(.system(size: 16, weight: .bold)).foregroundStyle(CapTheme.ink)
                                        Spacer()
                                        if let s = job.stat {
                                            Text(s).font(.system(size: 11, weight: .heavy, design: .monospaced))
                                                .foregroundStyle(CapTheme.red)
                                        }
                                    }
                                    Text(job.blurb).font(.system(size: 13)).foregroundStyle(CapTheme.mute)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 14).fill(CapTheme.bubble))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(CapTheme.line))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }
                    Text("Da Capo only ever creates its own playlists. It can't delete your songs or change playlists you made — Apple doesn't allow that, and neither do we.")
                        .font(.system(size: 12)).foregroundStyle(CapTheme.mute.opacity(0.8))
                        .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 24)
                }
            }
            .background(CapTheme.bg)
            .navigationTitle("What Cap does")
        }
    }
}

/// Lets the Jobs screen hand an intent to the chat tab.
@MainActor
final class Router: ObservableObject {
    @Published var tab = 0
    @Published var pending: String?
    func run(_ intent: String) { pending = intent; tab = 0 }
}
