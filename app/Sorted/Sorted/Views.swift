import SwiftUI

// MARK: Scan

struct ScanView: View {
    @EnvironmentObject var model: LibraryModel
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("🗂️").font(.system(size: 72))
            Text("Da Capo").font(.system(size: 40, weight: .heavy, design: .rounded))
            Text("Your music library, finally organised.\nNothing leaves your phone.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            if model.stage == .scanning {
                ProgressView().padding(.top)
                Text(model.scanStatus).font(.footnote).foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            } else {
                Button { Task { await model.scan() } } label: {
                    Text("Scan my library").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).padding(.horizontal, 40).padding(.top)
                if let e = model.errorText {
                    Text(e).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center).padding(.horizontal)
                }
            }
            Spacer(); Spacer()
        }
        .padding()
    }
}

// MARK: Report

struct ReportView: View {
    @EnvironmentObject var model: LibraryModel
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ReportCard(report: model.report).padding(.horizontal)
                ShareLink(item: renderCard(), preview: SharePreview("My library, diagnosed", image: renderCard())) {
                    Label("Share report card", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).padding(.horizontal)
                Button { model.stage = .plan } label: {
                    Text("Show me the plan →").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Your library")
        .navigationBarTitleDisplayMode(.inline)
    }
    @MainActor func renderCard() -> Image {
        let r = ImageRenderer(content: ReportCard(report: model.report, forExport: true).frame(width: 420))
        r.scale = 3
        if let ui = r.uiImage { return Image(uiImage: ui) }
        return Image(systemName: "photo")
    }
}

struct ReportCard: View {
    let report: Report
    var forExport = false
    private var yearsSpan: String {
        guard let o = report.oldestAdd else { return "—" }
        let y = Calendar.current.dateComponents([.year], from: o, to: .now).year ?? 0
        return y > 0 ? "\(y) years of collecting" : "a young library"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("MY LIBRARY, DIAGNOSED").font(.system(.caption, design: .rounded).weight(.heavy)).kerning(1.2)
                Spacer()
                Text("🗂️")
            }
            HStack(spacing: 0) {
                stat("\(report.total)", "songs")
                stat("\(report.artists)", "artists")
                stat("\(report.totalMinutes / 60)h", "of music")
            }
            Divider()
            row("🕳️", "\(report.inNoPlaylist) songs in no playlist")
            row("💤", "\(report.neverPlayed) never played")
            row("💎", "\(report.forgotten) forgotten favourites")
            row("👯", "\(report.duplicates) duplicates")
            if let top = report.topArtists.first {
                row("🏆", "\(top.0), \(top.1) songs — you have a type")
            }
            row("📅", yearsSpan)
            if !report.genres.isEmpty {
                Divider()
                HStack(spacing: 6) {
                    ForEach(report.genres.prefix(4), id: \.0) { g in
                        Text("\(g.0) \(pct(g.1))").font(.system(.caption2, design: .rounded).weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(Color(red: 0.83, green: 0.39, blue: 0.10).opacity(0.14)))
                    }
                }
            }
            if forExport {
                Text("Da Capo — play your library again · dacapo.fm").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.quaternary))
    }
    func pct(_ n: Int) -> String { report.total > 0 ? "\(Int(round(Double(n) * 100 / Double(report.total))))%" : "" }
    func stat(_ v: String, _ l: String) -> some View {
        VStack { Text(v).font(.system(.title, design: .rounded).weight(.heavy)); Text(l).font(.caption).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity)
    }
    func row(_ e: String, _ t: String) -> some View {
        HStack(spacing: 10) { Text(e); Text(t).font(.system(.subheadline, design: .rounded)) }
    }
}

// MARK: Plan

struct PlanView: View {
    @EnvironmentObject var model: LibraryModel
    @EnvironmentObject var ent: Entitlements
    @State private var showPaywall = false
    var body: some View {
        List {
            if MoodClassifier.isAvailable && !model.moodsAdded {
                Section {
                    if let p = model.moodProgress {
                        HStack {
                            ProgressView(value: Double(p.done), total: Double(max(p.total, 1)))
                            Text("\(p.done)/\(p.total) artists").font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Button { Task { await model.addMoodBuckets() } } label: {
                            Label("Add mood playlists", systemImage: "sparkles")
                        }
                    }
                } footer: {
                    Text("Runs entirely on this phone with Apple Intelligence. Artists the model doesn't truly know are left out rather than guessed.")
                }
            }
            Section(footer: Text("Sorted only creates new playlists — it never touches your existing ones. The 🗑️ playlist is a review queue: open it in Music and delete what you don't want.")) {
                ForEach($model.buckets) { $b in
                    HStack {
                        Text(b.emoji)
                        VStack(alignment: .leading) {
                            TextField("Name", text: $b.name).font(.headline)
                            Text("\(b.tracks.count) songs\(b.kind == .duplicates ? " · review queue" : "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $b.enabled).labelsHidden()
                    }
                }
            }
        }
        .navigationTitle("The plan")
        .sheet(isPresented: $showPaywall) { PaywallView { Task { await model.apply() } } }
        .safeAreaInset(edge: .bottom) {
            Button {
                if ent.unlocked { Task { await model.apply() } } else { showPaywall = true }
            } label: {
                Text("Create \(model.buckets.filter(\.enabled).count) playlists")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).padding()
            .background(.bar)
        }
    }
}

// MARK: Apply

struct ApplyView: View {
    @EnvironmentObject var model: LibraryModel
    var body: some View {
        VStack(spacing: 16) {
            if model.stage == .applying {
                ProgressView().controlSize(.large)
                Text("Building your playlists…").foregroundStyle(.secondary)
            } else {
                Text("🎉").font(.system(size: 64))
                Text("Da capo. 🎶").font(.system(.largeTitle, design: .rounded).weight(.heavy))
            }
            List(model.applyLog, id: \.self) { Text($0).font(.subheadline) }
                .listStyle(.plain).frame(maxHeight: 300)
            if model.stage == .done {
                Button { model.stage = .report } label: { Text("Back to report") }
            }
        }
        .padding()
        .navigationBarBackButtonHidden(model.stage == .applying)
    }
}
