import SwiftUI

enum Swiss {
    static let ink = Color(red: 0.067, green: 0.071, blue: 0.078)
    static let red = Color(red: 0.91, green: 0.27, blue: 0.11)
    static let paper = Color.white
}

struct SwissButton: View {
    let title: String
    var subtitle: String? = nil
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title).font(.system(size: 15, weight: .heavy)).tracking(1.4)
                if let sub = subtitle { Text(sub).font(.system(size: 10, weight: .semibold)).tracking(0.5).opacity(0.65) }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(Rectangle().fill(disabled ? Swiss.ink.opacity(0.35) : Swiss.ink))
        }
        .disabled(disabled)
    }
}

// MARK: Scan

struct ScanView: View {
    @EnvironmentObject var model: LibraryModel
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    HStack(spacing: 7) { Rectangle().fill(Swiss.red).frame(width: 14, height: 14); Text("D.C.").font(.system(size: 13, weight: .heavy)).tracking(1) }
                    Spacer()
                    Text("EST. 2026").font(.system(size: 9, weight: .heavy)).tracking(1.4).foregroundStyle(Swiss.ink.opacity(0.45))
                }
                Text("DA CAPO")
                    .font(.system(size: 52, weight: .black)).tracking(-1)
                    .padding(.top, 6)
                Rectangle().fill(Swiss.ink).frame(height: 3).padding(.top, 6)
                Text("Your music library, finally organised.")
                    .font(.system(size: 15, weight: .semibold)).padding(.top, 12)
                Text("Nothing leaves your phone.")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Swiss.ink.opacity(0.5))
                if model.stage == .scanning {
                    HStack(spacing: 10) {
                        ProgressView().tint(Swiss.red)
                        Text(model.scanStatus).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                            .contentTransition(.numericText()).foregroundStyle(Swiss.ink.opacity(0.6))
                    }.padding(.top, 24)
                } else {
                    SwissButton(title: "SCAN MY LIBRARY") { Task { await model.scan() } }
                        .padding(.top, 24)
                    if let e = model.errorText {
                        Text(e).font(.footnote).foregroundStyle(Swiss.red).padding(.top, 10)
                    }
                }
                HStack {
                    Text("READ-ONLY SCAN").font(.system(size: 8.5, weight: .heavy)).tracking(1)
                    Spacer()
                    Text("DACAPO.FM").font(.system(size: 8.5, weight: .heavy)).tracking(1).foregroundStyle(Swiss.red)
                }
                .foregroundStyle(Swiss.ink.opacity(0.45))
                .padding(.top, 22)
            }
            .foregroundStyle(Swiss.ink)
            .padding(26)
            .background(Swiss.paper)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
            .padding(.horizontal, 24)
            Spacer(); Spacer()
        }
    }
}

// MARK: Report

struct ReportView: View {
    @EnvironmentObject var model: LibraryModel
    @State private var showDupes = false
    @State private var showRepeats = false
    @State private var showSleepers = false
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let d = model.delta {
                    DeltaBanner(d: d).padding(.horizontal)
                }
                ReportCard(report: model.report, personality: model.personality).padding(.horizontal)
                    .task { await model.makePersonality() }
                VStack(spacing: 8) {
                    if !model.report.dupeExamples.isEmpty {
                        Button { showDupes = true } label: {
                            Label("See your \(model.report.duplicates) duplicates", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered)
                    }
                    HStack(spacing: 8) {
                        Button { showRepeats = true } label: {
                            Label("Most played", systemImage: "repeat").frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered)
                        Button { showSleepers = true } label: {
                            Label("\(model.report.neverPlayed) never played", systemImage: "zzz").frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered)
                    }
                }.padding(.horizontal)
                ShareLink(item: renderCard(), preview: SharePreview("My library, diagnosed", image: renderCard())) {
                    Label("Share report card", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Your library")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: model.report.scannedAt)
        .refreshable { await model.scan() }
        .sheet(isPresented: $showDupes) { DupesSheet(report: model.report) }
        .sheet(isPresented: $showRepeats) { RepeatsSheet() }
        .sheet(isPresented: $showSleepers) { SleepersSheet() }
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
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    // Swiss sheet: white stock, black ink, one red — always, in both modes. It's an artifact, not a view.
    private let paper = Color.white
    private let ink = Color(red: 0.067, green: 0.071, blue: 0.078)
    private let inkSoft = Color(red: 0.067, green: 0.071, blue: 0.078).opacity(0.55)
    private let hairline = Color(red: 0.067, green: 0.071, blue: 0.078).opacity(0.16)
    private let red = Color(red: 0.91, green: 0.27, blue: 0.11)

    private var yearsSpan: String {
        guard let o = report.oldestAdd else { return "—" }
        let y = Calendar.current.dateComponents([.year], from: o, to: .now).year ?? 0
        return y > 0 ? "\(y) YRS" : "<1 YR"
    }
    private func fmt(_ n: Int) -> String { n.formatted(.number.grouping(.automatic)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            reveal(0) { VStack(alignment: .leading, spacing: 0) {
                HStack {
                    kick("MY LIBRARY")
                    Spacer()
                    kick("DA CAPO").foregroundStyle(red)
                }
                Rectangle().fill(ink).frame(height: 3).padding(.top, 8)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(fmt(report.total))
                        .font(.system(size: 58, weight: .black)).tracking(-1.5)
                        .monospacedDigit().contentTransition(.numericText())
                    Text("SONGS").font(.system(size: 12, weight: .heavy)).tracking(1.2).baselineOffset(26)
                }
                .padding(.top, 10)
            } }
            reveal(1) { VStack(spacing: 0) {
                Rectangle().fill(ink).frame(height: 1).padding(.top, 12)
                HStack(spacing: 0) {
                    cell(fmt(report.artists), "ARTISTS")
                    divider()
                    cell("\(report.totalMinutes / 60) H", "OF MUSIC")
                    divider()
                    cell(yearsSpan, "COLLECTING")
                }
                Rectangle().fill(hairline).frame(height: 1)
                HStack(spacing: 0) {
                    cell(fmt(report.inNoPlaylist), "UNFILED")
                    divider()
                    cell(fmt(report.neverPlayed), "NEVER PLAYED")
                    divider()
                    cell(fmt(report.duplicates), "DUPLICATES", accent: report.duplicates > 0)
                }
                Rectangle().fill(hairline).frame(height: 1)
            } }
            reveal(2) { VStack(alignment: .leading, spacing: 6) {
                HStack {
                    kick("HEALTH")
                    Spacer()
                    Text("\(report.health)/100").font(.system(size: 13, weight: .heavy)).monospacedDigit()
                        .contentTransition(.numericText(value: Double(report.health)))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(hairline)
                        Rectangle().fill(red).frame(width: max(4, geo.size.width * CGFloat(report.health) / 100))
                    }
                }.frame(height: 10)
            }.padding(.top, 14) }
            if let line = personality {
                reveal(3) { Text(line)
                    .font(.system(size: 13, weight: .medium)).italic()
                    .foregroundStyle(inkSoft)
                    .padding(.top, 12) }
            }
            if !report.genres.isEmpty {
                reveal(4) { VStack(alignment: .leading, spacing: 7) {
                    kick("GENRES").padding(.bottom, 2)
                    let maxG = report.genres.first?.count ?? 1
                    ForEach(Array(report.genres.prefix(5).enumerated()), id: \.element.name) { i, g in
                        HStack(spacing: 10) {
                            Text(g.name).font(.system(size: 12, weight: .bold))
                                .frame(width: 92, alignment: .leading).lineLimit(1)
                            GeometryReader { geo in
                                Rectangle().fill(i == 0 ? red : ink)
                                    .frame(width: max(4, geo.size.width * CGFloat(g.count) / CGFloat(maxG)), height: 10)
                                    .frame(maxHeight: .infinity, alignment: .center)
                            }
                            Text(pct(g.count)).font(.system(size: 11, weight: .heavy)).foregroundStyle(inkSoft)
                                .frame(width: 36, alignment: .trailing).monospacedDigit()
                        }.frame(height: 15)
                    }
                }.padding(.top, 18) }
            }
            if report.decades.count >= 2 {
                reveal(5) { VStack(alignment: .leading, spacing: 6) {
                    kick("DECADES")
                    let maxD = report.decades.map(\.count).max() ?? 1
                    HStack(alignment: .bottom, spacing: 5) {
                        ForEach(report.decades, id: \.name) { d in
                            VStack(spacing: 3) {
                                Text(fmt(d.count)).font(.system(size: 8, weight: .heavy)).foregroundStyle(inkSoft).monospacedDigit()
                                Rectangle().fill(ink).frame(height: max(4, 44 * CGFloat(d.count) / CGFloat(maxD)))
                                Text(d.name).font(.system(size: 9, weight: .heavy)).foregroundStyle(inkSoft)
                            }.frame(maxWidth: .infinity)
                        }
                    }
                }.padding(.top, 18) }
            }
            if !report.topArtists.isEmpty {
                reveal(6) { VStack(alignment: .leading, spacing: 7) {
                    kick("ON HEAVY ROTATION")
                    let maxA = report.topArtists.first?.count ?? 1
                    ForEach(report.topArtists.prefix(5), id: \.name) { a in
                        HStack(spacing: 10) {
                            Text(a.name).font(.system(size: 12, weight: .bold))
                                .frame(width: 110, alignment: .leading).lineLimit(1)
                            GeometryReader { geo in
                                Rectangle().fill(ink.opacity(0.45))
                                    .frame(width: max(4, geo.size.width * CGFloat(a.count) / CGFloat(maxA)), height: 10)
                                    .frame(maxHeight: .infinity, alignment: .center)
                            }
                            Text("\(a.count)").font(.system(size: 11, weight: .heavy)).foregroundStyle(inkSoft)
                                .frame(width: 28, alignment: .trailing).monospacedDigit()
                        }.frame(height: 15)
                    }
                }.padding(.top, 18) }
            }
            reveal(7) { VStack(spacing: 0) {
                Rectangle().fill(ink).frame(height: 3).padding(.top, 16)
                HStack {
                    kick(forExport ? "SCANNED ON-DEVICE" : "NOTHING LEAVES YOUR PHONE")
                    Spacer()
                    kick("DACAPO.FM").foregroundStyle(red)
                }.padding(.top, 8)
            } }
        }
        .foregroundStyle(ink)
        .padding(22)
        .background(paper)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .onAppear { if forExport || reduceMotion { revealed = true } else { withAnimation(.snappy(duration: 0.5)) { revealed = true } } }
    }

    func reveal<V: View>(_ i: Double, @ViewBuilder _ v: () -> V) -> some View {
        v().opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 14)
            .animation(reduceMotion ? nil : .snappy(duration: 0.55).delay(i * 0.07), value: revealed)
    }
    func pct(_ n: Int) -> String { report.total > 0 ? "\(Int(round(Double(n) * 100 / Double(report.total))))%" : "" }
    func kick(_ t: String) -> some View {
        Text(t).font(.system(size: 10, weight: .heavy)).tracking(1.4)
    }
    func cell(_ v: String, _ l: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.system(size: 20, weight: .black)).tracking(-0.5).monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(accent ? red : ink)
            Text(l).font(.system(size: 8.5, weight: .heavy)).tracking(1).foregroundStyle(inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }
    func divider() -> some View { Rectangle().fill(hairline).frame(width: 1).padding(.vertical, 6) }
}

struct DupesSheet: View {
    let report: Report
    @Environment(\.dismiss) var dismiss
    private let accent = Color(red: 0.91, green: 0.27, blue: 0.11)
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

struct RepeatsSheet: View {
    @EnvironmentObject var model: LibraryModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            List {
                let top = model.tracks.filter { $0.playCount > 0 }.sorted { $0.playCount > $1.playCount }.prefix(50)
                if top.isEmpty {
                    Text("No play counts yet — plays on this device will show up here.").foregroundStyle(.secondary)
                }
                ForEach(Array(top)) { t in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.title).font(.headline).lineLimit(1)
                            Text(t.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text("\(t.playCount)×").font(.system(.headline, design: .rounded).weight(.heavy))
                            .foregroundStyle(Color(red: 0.91, green: 0.27, blue: 0.11)).monospacedDigit()
                    }
                }
            }
            .navigationTitle("On repeat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct SleepersSheet: View {
    @EnvironmentObject var model: LibraryModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            List {
                let sleepers = model.tracks.filter { $0.playCount == 0 }.sorted { ($0.added ?? .now) < ($1.added ?? .now) }
                Section {
                    ForEach(sleepers) { t in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.title).font(.headline).lineLimit(1)
                                Text(t.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if let a = t.added {
                                Text("added \(a.formatted(.dateTime.month(.abbreviated).year()))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    Text("You saved these for a reason. The 💎 Rediscover playlist starts here.")
                }
            }
            .navigationTitle("Never played")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct DeltaBanner: View {
    let d: Delta
    private let ink = Color(red: 0.067, green: 0.071, blue: 0.078)
    private let red = Color(red: 0.91, green: 0.27, blue: 0.11)
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("SINCE \(d.since.formatted(date: .abbreviated, time: .omitted).uppercased())")
                .font(.system(size: 9, weight: .heavy)).tracking(1.3).foregroundStyle(ink.opacity(0.5))
            HStack(spacing: 16) {
                if d.songs != 0 { item(d.songs > 0 ? "+\(d.songs)" : "\(d.songs)", "SONGS") }
                if d.duplicates > 0 { item("+\(d.duplicates)", "DUPES", accent: true) }
                if d.unfiled != 0 { item(d.unfiled > 0 ? "+\(d.unfiled)" : "\(-d.unfiled)", d.unfiled > 0 ? "UNFILED" : "FILED") }
                if d.healthFrom != d.healthTo { item("\(d.healthFrom)→\(d.healthTo)", "HEALTH", accent: d.healthTo > d.healthFrom) }
                Spacer()
            }
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 22).padding(.vertical, 12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) { Rectangle().fill(red).frame(width: 3).clipShape(RoundedRectangle(cornerRadius: 2)) }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }
    func item(_ v: String, _ l: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(v).font(.system(size: 16, weight: .black)).monospacedDigit().foregroundStyle(accent ? red : ink)
            Text(l).font(.system(size: 8, weight: .heavy)).tracking(1).foregroundStyle(ink.opacity(0.5))
        }
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
        .sensoryFeedback(.success, trigger: model.created.count)
        .sheet(isPresented: $showPaywall) { PaywallView { Task { await model.apply() } } }
        .safeAreaInset(edge: .bottom) {
            if !model.buckets.filter(\.enabled).isEmpty {
              VStack(spacing: 0) {
                HStack(spacing: 5) {
                    Text("HEALTH").font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(.secondary)
                    Text("\(model.report.health)").font(.system(size: 13, weight: .black)).monospacedDigit()
                    Text("→").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                    Text("\(model.report.projectedHealth)").font(.system(size: 13, weight: .black)).monospacedDigit().foregroundStyle(Swiss.red)
                    Text("· \(model.report.inNoPlaylist) unfiled → 0 · \(model.report.duplicates) dupes queued")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
                if model.applying {
                    SwissButton(title: "CREATING…", disabled: true) {}
                } else {
                    SwissButton(title: "CREATE \(model.buckets.filter(\.enabled).count) PLAYLISTS",
                                subtitle: ent.unlocked ? nil : "one-time unlock") {
                        if ent.unlocked { Task { await model.apply() } } else { showPaywall = true }
                    }
                }
              }
              .padding()
              .background(.bar)
            }
        }
    }
}
