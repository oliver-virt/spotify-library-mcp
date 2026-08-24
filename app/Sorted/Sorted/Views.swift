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
    @State private var showDupes = false
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let d = model.delta {
                    DeltaBanner(d: d).padding(.horizontal)
                }
                ReportCard(report: model.report, personality: model.personality).padding(.horizontal)
                    .task { await model.makePersonality() }
                if !model.report.dupeExamples.isEmpty {
                    Button { showDupes = true } label: {
                        Label("See your \(model.report.duplicates) duplicates", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).padding(.horizontal)
                }
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
        .sheet(isPresented: $showDupes) { DupesSheet(report: model.report) }
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
            HStack(spacing: 10) {
                Text("LIBRARY HEALTH").font(.system(size: 11, design: .rounded).weight(.heavy)).kerning(1.1).foregroundStyle(.secondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.tertiarySystemGroupedBackground))
                        Capsule().fill(accent).frame(width: max(8, geo.size.width * CGFloat(report.health) / 100))
                    }
                }.frame(height: 8)
                Text("\(report.health)/100").font(.system(.caption, design: .rounded).weight(.heavy)).monospacedDigit()
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
                let maxG = report.genres.first?.count ?? 1
                VStack(spacing: 7) {
                    ForEach(report.genres.prefix(5), id: \.name) { g in
                        HStack(spacing: 8) {
                            Text(g.name).font(.system(.caption, design: .rounded).weight(.semibold))
                                .frame(width: 92, alignment: .leading).lineLimit(1)
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(accent)
                                    .frame(width: max(6, geo.size.width * CGFloat(g.count) / CGFloat(maxG)), height: 8)
                                    .frame(maxHeight: .infinity, alignment: .center)
                            }
                            Text(pct(g.count)).font(.system(.caption2, design: .rounded).weight(.bold))
                                .foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                                .monospacedDigit()
                        }
                        .frame(height: 16)
                    }
                }
            }
            if report.decades.count >= 2 {
                section("DECADES")
                let maxD = report.decades.map(\.count).max() ?? 1
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(report.decades, id: \.name) { d in
                        VStack(spacing: 4) {
                            Text("\(d.count)").font(.system(size: 9, design: .rounded).weight(.bold))
                                .foregroundStyle(.secondary).monospacedDigit()
                            RoundedRectangle(cornerRadius: 3)
                                .fill(accent.opacity(0.85))
                                .frame(height: max(6, 52 * CGFloat(d.count) / CGFloat(maxD)))
                            Text(d.name).font(.system(size: 10, design: .rounded).weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            if !report.topArtists.isEmpty {
                section("ON HEAVY ROTATION")
                let maxA = report.topArtists.first?.count ?? 1
                VStack(spacing: 7) {
                    ForEach(report.topArtists.prefix(5), id: \.name) { a in
                        HStack(spacing: 8) {
                            Text(a.name).font(.system(.caption, design: .rounded).weight(.semibold))
                                .frame(width: 110, alignment: .leading).lineLimit(1)
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(accent.opacity(0.55))
                                    .frame(width: max(6, geo.size.width * CGFloat(a.count) / CGFloat(maxA)), height: 8)
                                    .frame(maxHeight: .infinity, alignment: .center)
                            }
                            Text("\(a.count)").font(.system(.caption2, design: .rounded).weight(.bold))
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

struct DupesSheet: View {
    let report: Report
    @Environment(\.dismiss) var dismiss
    private let accent = Color(red: 0.83, green: 0.39, blue: 0.10)
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(report.dupeExamples) { d in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(d.title) — \(d.artist)").font(.headline)
                            HStack(spacing: 6) {
                                Text(d.albumA).lineLimit(1)
                                Image(systemName: "plus").font(.caption2)
                                Text(d.albumB).lineLimit(1)
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            Text("same song · two releases").font(.caption2).foregroundStyle(accent)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("You didn't add these twice — Apple's catalog did")
                } footer: {
                    Text("Create the 🗑️ Review & Delete playlist and these land in one place. Open it in Music, select all, delete — a minute, not an afternoon.")
                }
            }
            .navigationTitle("Your duplicates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct DeltaBanner: View {
    let d: Delta
    private let accent = Color(red: 0.83, green: 0.39, blue: 0.10)
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SINCE \(d.since.formatted(date: .abbreviated, time: .omitted).uppercased())")
                .font(.system(size: 10, design: .rounded).weight(.heavy)).kerning(1).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                if d.songs != 0 { chip(d.songs > 0 ? "+\(d.songs) songs" : "\(d.songs) songs") }
                if d.duplicates > 0 { chip("+\(d.duplicates) duplicates") }
                if d.unfiled != 0 { chip(d.unfiled > 0 ? "+\(d.unfiled) unfiled" : "\(-d.unfiled) filed ✓") }
                if d.healthFrom != d.healthTo {
                    chip("health \(d.healthFrom) → \(d.healthTo) \(d.healthTo > d.healthFrom ? "📈" : "📉")")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(accent.opacity(0.10)))
    }
    func chip(_ t: String) -> some View {
        Text(t).font(.system(.caption, design: .rounded).weight(.bold)).foregroundStyle(accent)
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
              VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text("Health \(model.report.health)").fontWeight(.bold)
                    Image(systemName: "arrow.right")
                    Text("\(model.report.projectedHealth)").fontWeight(.heavy).foregroundStyle(Color(red: 0.83, green: 0.39, blue: 0.10))
                    Text("· \(model.report.inNoPlaylist) unfiled → 0 · \(model.report.duplicates) dupes queued")
                        .foregroundStyle(.secondary)
                }
                .font(.system(.caption, design: .rounded))
                Button {
                    if ent.unlocked { Task { await model.apply() } } else { showPaywall = true }
                } label: {
                    Group {
                        if model.applying { ProgressView().tint(.white) }
                        else { Text("Create \(model.buckets.filter(\.enabled).count) playlists").font(.headline) }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).disabled(model.applying)
              }
              .padding()
              .background(.bar)
            }
        }
    }
}
