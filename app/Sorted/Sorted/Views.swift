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
                ReportCard(report: model.report, personality: model.personality).padding(.horizontal)
                    .task { await model.makePersonality() }
                ShareLink(item: renderCard(), preview: SharePreview("My library, diagnosed", image: renderCard())) {
                    Label("Share report card", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Your library")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.scan() }
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button { Task { await model.scan() } } label: { Image(systemName: "arrow.clockwise") }
        } }
    }
    @MainActor func renderCard() -> Image {
        let r = ImageRenderer(content: ReportCard(report: model.report, personality: model.personality, forExport: true).frame(width: 420))
        r.scale = 3
        if let ui = r.uiImage { return Image(uiImage: ui) }
        return Image(systemName: "photo")
    }
}

struct ReportCard: View {
    let report: Report
    var personality: String? = nil
    var forExport = false
    private let accent = Color(red: 0.83, green: 0.39, blue: 0.10)
    private var yearsSpan: String {
        guard let o = report.oldestAdd else { return "—" }
        let y = Calendar.current.dateComponents([.year], from: o, to: .now).year ?? 0
        return y > 0 ? "\(y) yrs" : "<1 yr"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("MY LIBRARY, DIAGNOSED").font(.system(.caption, design: .rounded).weight(.heavy)).kerning(1.2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("🗂️")
            }
            HStack(spacing: 0) {
                hero("\(report.total)", "songs")
                hero("\(report.artists)", "artists")
                hero("\(report.totalMinutes / 60)h", "of music")
                hero(yearsSpan, "collecting")
            }
            if let line = personality {
                Text("“\(line)”")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold)).italic()
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(accent.opacity(0.10)))
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                tile("🕳️", report.inNoPlaylist, "in no playlist")
                tile("💤", report.neverPlayed, "never played")
                tile("💎", report.forgotten, "forgotten gems")
                tile("👯", report.duplicates, "duplicates")
            }
            if !report.genres.isEmpty {
                section("GENRES")
                let maxG = report.genres.first?.1 ?? 1
                VStack(spacing: 7) {
                    ForEach(report.genres.prefix(5), id: \.0) { g in
                        HStack(spacing: 8) {
                            Text(g.0).font(.system(.caption, design: .rounded).weight(.semibold))
                                .frame(width: 92, alignment: .leading).lineLimit(1)
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(accent)
                                    .frame(width: max(6, geo.size.width * CGFloat(g.1) / CGFloat(maxG)), height: 8)
                                    .frame(maxHeight: .infinity, alignment: .center)
                            }
                            Text(pct(g.1)).font(.system(.caption2, design: .rounded).weight(.bold))
                                .foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                                .monospacedDigit()
                        }
                        .frame(height: 16)
                    }
                }
            }
            if report.decades.count >= 2 {
                section("DECADES")
                let maxD = report.decades.map(\.1).max() ?? 1
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(report.decades, id: \.0) { d in
                        VStack(spacing: 4) {
                            Text("\(d.1)").font(.system(size: 9, design: .rounded).weight(.bold))
                                .foregroundStyle(.secondary).monospacedDigit()
                            RoundedRectangle(cornerRadius: 3)
                                .fill(accent.opacity(0.85))
                                .frame(height: max(6, 52 * CGFloat(d.1) / CGFloat(maxD)))
                            Text(d.0).font(.system(size: 10, design: .rounded).weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            if !report.topArtists.isEmpty {
                section("ON HEAVY ROTATION")
                let maxA = report.topArtists.first?.1 ?? 1
                VStack(spacing: 7) {
                    ForEach(report.topArtists.prefix(5), id: \.0) { a in
                        HStack(spacing: 8) {
                            Text(a.0).font(.system(.caption, design: .rounded).weight(.semibold))
                                .frame(width: 110, alignment: .leading).lineLimit(1)
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(accent.opacity(0.55))
                                    .frame(width: max(6, geo.size.width * CGFloat(a.1) / CGFloat(maxA)), height: 8)
                                    .frame(maxHeight: .infinity, alignment: .center)
                            }
                            Text("\(a.1)").font(.system(.caption2, design: .rounded).weight(.bold))
                                .foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
                                .monospacedDigit()
                        }
                        .frame(height: 16)
                    }
                }
            }
            if forExport {
                Text("Da Capo — play your library again · dacapo.fm")
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.quaternary))
    }
    func pct(_ n: Int) -> String { report.total > 0 ? "\(Int(round(Double(n) * 100 / Double(report.total))))%" : "" }
    func hero(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.system(.title2, design: .rounded).weight(.heavy)).monospacedDigit()
            Text(l).font(.system(size: 11)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
    func tile(_ e: String, _ n: Int, _ l: String) -> some View {
        HStack(spacing: 10) {
            Text(e).font(.title3)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(n)").font(.system(.headline, design: .rounded).weight(.heavy)).monospacedDigit()
                Text(l).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemGroupedBackground)))
    }
    func section(_ t: String) -> some View {
        Text(t).font(.system(size: 11, design: .rounded).weight(.heavy)).kerning(1.1).foregroundStyle(.secondary)
    }
}

// MARK: Playlists tab

struct PlaylistsTab: View {
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
            if !model.buckets.isEmpty {
                Section("Suggested") {
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
            } else if model.applyLog.isEmpty {
                Section { Text("Nothing to suggest — rescan after your library grows.").foregroundStyle(.secondary) }
            }
            if !model.applyLog.isEmpty {
                Section("Last run") { ForEach(model.applyLog, id: \.self) { Text($0).font(.subheadline) } }
            }
            if !model.created.isEmpty {
                Section {
                    ForEach(model.created) { c in
                        HStack {
                            Text(c.name)
                            Spacer()
                            Text("\(c.count) · \(c.date.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: { Text("Created by Da Capo") } footer: { Text("These live in Apple Music. Deleting one there is always safe — Da Capo never touches the rest of your library.") }
            }
        }
        .navigationTitle("Playlists")
        .sheet(isPresented: $showPaywall) { PaywallView { Task { await model.apply() } } }
        .safeAreaInset(edge: .bottom) {
            if !model.buckets.filter(\.enabled).isEmpty {
                Button {
                    if ent.unlocked { Task { await model.apply() } } else { showPaywall = true }
                } label: {
                    Group {
                        if model.applying { ProgressView().tint(.white) }
                        else { Text("Create \(model.buckets.filter(\.enabled).count) playlists").font(.headline) }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).disabled(model.applying).padding()
                .background(.bar)
            }
        }
    }
}
