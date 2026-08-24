import SwiftUI
import StoreKit

// Chat-first shell. Chips are deterministic intents on LibraryModel — no AI needed.
// Free-text is a stub until the Foundation Models layer lands.

enum CapTheme {
    static let bg = Color(red: 0.086, green: 0.075, blue: 0.059)      // #16130F
    static let bubble = Color(red: 0.133, green: 0.114, blue: 0.090)  // #221D17
    static let line = Color(red: 0.184, green: 0.157, blue: 0.125)
    static let ink = Color(red: 0.949, green: 0.914, blue: 0.859)     // #F2E9DB
    static let mute = Color(red: 0.561, green: 0.522, blue: 0.455)
    static let red = Color(red: 0.91, green: 0.27, blue: 0.11)
    static let paper = Color(red: 0.965, green: 0.941, blue: 0.886)   // #F6F0E2
    static let paperInk = Color(red: 0.141, green: 0.118, blue: 0.090)
}

struct ChatMsg: Identifiable {
    enum Kind {
        case user(String)
        case cap(String)
        case plan
        case report
        case rediscover([Track])
        case dupes
    }
    let id = UUID()
    let kind: Kind
}

@MainActor
final class ChatModel: ObservableObject {
    @Published var messages: [ChatMsg] = []
    @Published var thinking = false
    @Published var chips: [String] = ChatModel.homeChips
    static let homeChips = ["Sort my library", "Find duplicates", "What did I forget?", "How do I listen?"]

    func cap(_ t: String) { messages.append(ChatMsg(kind: .cap(t))) }

    /// Typed input: on-device model routes to a tool; tools stay deterministic.
    private func freeText(_ text: String, lib: LibraryModel) async {
        messages.append(ChatMsg(kind: .user(text)))
        guard MoodClassifier.isAvailable else {
            cap("Not my counter — I do five things: sort, playlists, duplicates, forgotten songs, and your listening report. Pick one below.")
            chips = Self.homeChips
            return
        }
        thinking = true
        let top = lib.report.topArtists.first
        let song = lib.report.topSongs.first
        let ctx = "\(lib.report.total) songs, \(lib.report.artists) artists, \(lib.report.duplicates) duplicates, \(lib.report.neverPlayed) never played, top artist \(top?.name ?? "unknown") (\(top?.count ?? 0) songs), top song \(song?.name ?? "unknown") played \(song?.count ?? 0) times, health \(lib.report.health)/100."
        let out = await MoodClassifier.interpret(text, context: ctx)
        thinking = false
        guard let out else {
            cap("Not my counter — try one of the chips below.")
            chips = Self.homeChips
            return
        }
        cap(out.reply)
        switch out.intent {
        case "sort":
            messages.append(ChatMsg(kind: .plan))
            chips = ["Add mood playlists", "How do I listen?"]
        case "duplicates":
            if lib.report.duplicates > 0 { messages.append(ChatMsg(kind: .dupes)) }
            chips = Self.homeChips.filter { $0 != "Find duplicates" }
        case "rediscover":
            let r = lib.rediscoverList()
            if !r.isEmpty {
                messages.append(ChatMsg(kind: .rediscover(Array(r.prefix(6)))))
                chips = ["Make it a playlist", "Sort my library"]
            } else { chips = Self.homeChips }
        case "report":
            messages.append(ChatMsg(kind: .report))
            chips = Self.homeChips.filter { $0 != "How do I listen?" }
        default:
            chips = Self.homeChips
        }
    }

    func run(_ intent: String, lib: LibraryModel) async {
        let known = Self.homeChips + ["Make it a playlist", "Add mood playlists"]
        guard known.contains(intent) else { await freeText(intent, lib: lib); return }
        messages.append(ChatMsg(kind: .user(intent.lowercased())))
        thinking = true
        try? await Task.sleep(for: .milliseconds(500))
        thinking = false
        switch intent {
        case "Sort my library":
            let never = lib.report.neverPlayed
            cap("Done reading. \(lib.report.total.formatted()) songs\(never > 0 ? ", and \(never.formatted()) you have never played" : ""). Here is what I suggest:")
            messages.append(ChatMsg(kind: .plan))
            chips = ["Add mood playlists", "How do I listen?"]
        case "Find duplicates":
            if lib.report.duplicates == 0 { cap("Checked every song. No duplicates. Clean shelves.") }
            else {
                cap("Found \(lib.report.duplicates) duplicates. You didn't add them twice — Apple's catalog did. Same song, different releases:")
                messages.append(ChatMsg(kind: .dupes))
            }
            chips = Self.homeChips.filter { $0 != "Find duplicates" }
        case "What did I forget?":
            let r = lib.rediscoverList()
            if r.isEmpty { cap("Nothing forgotten yet — young library. Ask me again in a year.") }
            else {
                cap("Songs you saved and never came back to. My picks:")
                messages.append(ChatMsg(kind: .rediscover(Array(r.prefix(6)))))
            }
            chips = ["Make it a playlist", "Sort my library"]
        case "How do I listen?":
            cap("Pulled your real numbers. Apple hides play counts on iPhone; I don't:")
            messages.append(ChatMsg(kind: .report))
            chips = Self.homeChips.filter { $0 != "How do I listen?" }
        case "Make it a playlist":
            messages.append(ChatMsg(kind: .user("make it a playlist")))
            cap("On it — check Apple Music in a moment.")
            await lib.applyRediscoverOnly()
            cap("Done. 💎 Rediscover is in your playlists.")
            chips = Self.homeChips
        case "Add mood playlists":
            if MoodClassifier.isAvailable {
                cap("Give me a minute with your artists…")
                await lib.addMoodBuckets()
                cap("Added mood playlists to the plan above. Flip any off before you approve.")
            } else { cap("Mood sorting needs Apple Intelligence on this phone. The rest of the plan works without it.") }
            chips = ["How do I listen?"]
        default:
            await freeText(intent, lib: lib)
        }
    }
}

struct ChatView: View {
    @EnvironmentObject var lib: LibraryModel
    @EnvironmentObject var ent: Entitlements
    @StateObject var chat = ChatModel()
    @State private var input = ""
    @State private var showPaywall = false
    @State private var showWork = false

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if chat.messages.isEmpty { emptyState }
                        ForEach(chat.messages) { msg in MsgView(msg: msg, showPaywall: $showPaywall) }
                        if chat.thinking {
                            HStack(spacing: 8) {
                                capAvatar(28)
                                ProgressView().tint(CapTheme.mute)
                            }
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: chat.messages.count) { _, _ in withAnimation { proxy.scrollTo("end") } }
            }
            chipsRow
            composer
        }
        .background(CapTheme.bg)
        .sheet(isPresented: $showPaywall) { PaywallView { Task { await applyPlan() } } }
        .sheet(isPresented: $showWork) { WorkSheet() }
        .onChange(of: lib.created.count) { old, new in if new > old { requestReviewIfEarned() } }
        .preferredColorScheme(.dark)
    }

    var header: some View {
        HStack(spacing: 10) {
            capAvatar(32)
            Text("Da Capo").font(.system(size: 19, weight: .heavy)).foregroundStyle(CapTheme.ink)
            Spacer()
            Button { showWork = true } label: {
                Image(systemName: "archivebox").foregroundStyle(CapTheme.mute).frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(CapTheme.line).frame(height: 1) }
    }

    var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            capAvatar(64)
            Text("What should we do\nwith your music?")
                .font(.system(size: 28, weight: .heavy)).foregroundStyle(CapTheme.ink)
            Text("Five things I do: sort your library, build playlists, find duplicates, resurface forgotten songs, and report how you really listen. All on your phone.")
                .font(.system(size: 14.5)).foregroundStyle(CapTheme.mute).lineSpacing(3)
        }
        .padding(.top, 40)
    }

    var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chat.chips, id: \.self) { c in
                    Button { Task { await chat.run(c, lib: lib) } } label: {
                        Text(c).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CapTheme.mute)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(Capsule().fill(CapTheme.bubble))
                            .overlay(Capsule().stroke(CapTheme.line))
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }

    var composer: some View {
        HStack(spacing: 10) {
            TextField("Ask about your music…", text: $input)
                .font(.system(size: 15)).foregroundStyle(CapTheme.ink)
                .padding(.horizontal, 18).padding(.vertical, 13)
                .background(Capsule().fill(CapTheme.bubble))
                .overlay(Capsule().stroke(CapTheme.line))
                .onSubmit { send() }
            Button { send() } label: {
                Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 46, height: 46).background(Circle().fill(CapTheme.red))
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 8)
    }

    func send() {
        let t = input.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        input = ""
        Task { await chat.run(t, lib: lib) }
    }

    func applyPlan() async {
        await lib.apply()
        chat.cap("Done. \(lib.created.count) playlists are in Apple Music. Re-ask any time — they refresh, never duplicate.")
        requestReviewIfEarned()
    }

    /// Ask for a rating at the value moment (first successful apply), never at the paywall.
    func requestReviewIfEarned() {
        guard !lib.created.isEmpty, !UserDefaults.standard.bool(forKey: "dacapo.reviewAsked") else { return }
        UserDefaults.standard.set(true, forKey: "dacapo.reviewAsked")
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            AppStore.requestReview(in: scene)
        }
    }
}

func capAvatar(_ size: CGFloat) -> some View {
    Image("Cap").resizable().interpolation(.none)
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24))
}

struct MsgView: View {
    @EnvironmentObject var lib: LibraryModel
    @EnvironmentObject var ent: Entitlements
    let msg: ChatMsg
    @Binding var showPaywall: Bool

    var body: some View {
        switch msg.kind {
        case .user(let t):
            Text(t).font(.system(size: 15)).foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16, bottomTrailingRadius: 4, topTrailingRadius: 16).fill(CapTheme.red))
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .cap(let t):
            HStack(alignment: .top, spacing: 10) {
                capAvatar(28)
                Text(t).font(.system(size: 15)).foregroundStyle(CapTheme.ink).lineSpacing(3)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 4, bottomTrailingRadius: 16, topTrailingRadius: 16).fill(CapTheme.bubble))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .plan:
            PlanCard(showPaywall: $showPaywall).padding(.leading, 38)
        case .report:
            ReportCard(report: lib.report, personality: lib.personality, forExport: false)
                .frame(width: 300).padding(.leading, 38)
                .task { await lib.makePersonality() }
        case .rediscover(let tracks):
            PaperCard(title: "FORGOTTEN", right: "\(tracks.count) PICKS") {
                ForEach(tracks) { t in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.title).font(.system(size: 13, weight: .bold)).lineLimit(1)
                            Text(t.artist).font(.system(size: 11)).foregroundStyle(CapTheme.paperInk.opacity(0.55)).lineLimit(1)
                        }
                        Spacer()
                        if let a = t.added {
                            Text(a.formatted(.dateTime.month(.abbreviated).year()))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(CapTheme.paperInk.opacity(0.5))
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
            .padding(.leading, 38)
        case .dupes:
            PaperCard(title: "DUPLICATES", right: "\(lib.report.duplicates)") {
                ForEach(lib.report.dupeExamples.prefix(5)) { d in
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(d.title) — \(d.artist)").font(.system(size: 13, weight: .bold)).lineLimit(1)
                        Text("\(d.albumA) + \(d.albumB)").font(.system(size: 10.5)).foregroundStyle(CapTheme.paperInk.opacity(0.55)).lineLimit(1)
                    }
                    .padding(.vertical, 3)
                }
                Text("Approve the plan and these land in one review playlist.")
                    .font(.system(size: 11)).foregroundStyle(CapTheme.paperInk.opacity(0.6)).padding(.top, 6)
            }
            .padding(.leading, 38)
        }
    }
}

struct PaperCard<Content: View>: View {
    let title: String
    let right: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(2)
                Spacer()
                Text(right).font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(1)
            }
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) { Rectangle().fill(CapTheme.paperInk).frame(height: 2) }
            VStack(alignment: .leading, spacing: 2) { content }.padding(.top, 8)
        }
        .foregroundStyle(CapTheme.paperInk)
        .padding(16)
        .frame(width: 300, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(CapTheme.paper))
        .shadow(color: .black.opacity(0.4), radius: 10, y: 5)
    }
}

struct PlanCard: View {
    @EnvironmentObject var lib: LibraryModel
    @EnvironmentObject var ent: Entitlements
    @Binding var showPaywall: Bool
    var body: some View {
        PaperCard(title: "PLAN · TAP TO EDIT", right: "\(lib.buckets.filter(\.enabled).count) OF \(lib.buckets.count) ON") {
            ForEach($lib.buckets) { $b in
                HStack {
                    Text(b.name).font(.system(size: 13, weight: .semibold))
                        .strikethrough(!b.enabled)
                        .foregroundStyle(b.enabled ? CapTheme.paperInk : CapTheme.paperInk.opacity(0.45))
                    Spacer()
                    Text("\(b.displayCount)").font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(CapTheme.paperInk.opacity(0.6))
                    Toggle("", isOn: $b.enabled).labelsHidden().tint(CapTheme.red)
                        .scaleEffect(0.72).frame(width: 40, height: 24)
                }
            }
            Text("Creates new playlists only. Yours stay untouched.")
                .font(.system(size: 10.5)).foregroundStyle(CapTheme.paperInk.opacity(0.6)).padding(.top, 6)
            Button {
                if ent.unlocked { Task { await lib.apply() } } else { showPaywall = true }
            } label: {
                Group {
                    if lib.applying { ProgressView().tint(CapTheme.paper) }
                    else { Text("APPROVE").font(.system(size: 12, weight: .heavy, design: .monospaced)).tracking(2) }
                }
                .foregroundStyle(CapTheme.paper)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(RoundedRectangle(cornerRadius: 8).fill(CapTheme.paperInk))
            }
            .disabled(lib.applying || lib.buckets.filter(\.enabled).isEmpty)
            .padding(.top, 10)
        }
    }
}

struct WorkSheet: View {
    @EnvironmentObject var lib: LibraryModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            List {
                if lib.created.isEmpty {
                    Text("Nothing yet — approve a plan and it shows up here.").foregroundStyle(.secondary)
                } else {
                    Section("Playlists I made") {
                        ForEach(lib.created) { c in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.name).font(.system(size: 15, weight: .semibold))
                                    Text("\(c.count) songs · \(c.date.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
                Section { } footer: {
                    Text("Your own playlists never appear here — Da Capo doesn't touch them.")
                }
            }
            .navigationTitle("Cap's work")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}
