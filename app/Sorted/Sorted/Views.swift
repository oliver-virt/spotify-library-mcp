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
            if !report.topSongs.isEmpty {
                reveal(3.5) { VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        kick("MOST PLAYED")
                        Spacer()
                        kick("COUNTS APPLE HIDES").foregroundStyle(red)
                    }
                    ForEach(report.topSongs, id: \.name) { t in
                        HStack(spacing: 10) {
                            Text(t.name).font(.system(size: 12, weight: .bold)).lineLimit(1)
                            Spacer()
                            Text("×\(t.count)").font(.system(size: 13, weight: .black)).monospacedDigit().foregroundStyle(red)
                        }
                        .padding(.vertical, 3)
                        .overlay(alignment: .bottom) { Rectangle().fill(hairline).frame(height: 1) }
                    }
                }.padding(.top, 18) }
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
