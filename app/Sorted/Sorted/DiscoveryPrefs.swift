import SwiftUI

/// What kind of "new" the user wants. Defaults to everything on; remembered between runs.
struct DiscoveryPrefs: Codable, Equatable {
    var newFromArtists = true      // latest releases by artists they own
    var deepCuts = true            // songs by those artists they don't have
    var similarArtists = true      // neighbours of their favourites
    var appleRecs = true           // Apple's personal recommendations
    var charts = false             // popular now — off by default, it's the least personal
    var genres: [String] = []      // empty = any

    static let key = "dacapo.discoveryPrefs"
    static func load() -> DiscoveryPrefs {
        guard let d = UserDefaults.standard.data(forKey: key),
              let p = try? JSONDecoder().decode(DiscoveryPrefs.self, from: d) else { return DiscoveryPrefs() }
        return p
    }
    func save() { UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: Self.key) }
    var anySource: Bool { newFromArtists || deepCuts || similarArtists || appleRecs || charts }
}

struct DiscoveryPicker: View {
    @EnvironmentObject var lib: LibraryModel
    @Environment(\.dismiss) var dismiss
    @State private var prefs = DiscoveryPrefs.load()
    let onStart: (DiscoveryPrefs) -> Void

    private var libraryGenres: [String] {
        Array(lib.report.genres.prefix(8).map(\.name))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("WHERE TO LOOK") {
                        toggleRow("New releases from artists you own", "Albums you might have missed", $prefs.newFromArtists)
                        toggleRow("Songs you don't have by artists you love", "Their catalogue, minus what's yours", $prefs.deepCuts)
                        toggleRow("Artists similar to your favourites", "One step outward", $prefs.similarArtists)
                        toggleRow("Apple's recommendations for you", "Skipping the ones rebuilt from your library", $prefs.appleRecs)
                        toggleRow("Popular right now", "Least personal — off unless you want it", $prefs.charts)
                    }
                    if !libraryGenres.isEmpty {
                        section("NARROW IT (OPTIONAL)") {
                            Text(prefs.genres.isEmpty ? "Anything goes." : "Only: \(prefs.genres.joined(separator: ", "))")
                                .font(.system(size: 12)).foregroundStyle(CapTheme.mute)
                            FlowChips(items: libraryGenres, selected: $prefs.genres)
                        }
                    }
                }
                .padding(20)
            }
            .background(CapTheme.bg)
            .navigationTitle("What kind of new?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.tint(CapTheme.mute)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button {
                        prefs.save(); Haptics.medium(); dismiss(); onStart(prefs)
                    } label: {
                        Text(prefs.anySource ? "FIND SONGS" : "PICK AT LEAST ONE")
                            .font(.system(size: 13, weight: .heavy, design: .monospaced)).tracking(1.5)
                            .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(RoundedRectangle(cornerRadius: 12).fill(prefs.anySource ? CapTheme.red : CapTheme.line))
                    }
                    .disabled(!prefs.anySource)
                    Button("Just surprise me") {
                        var p = DiscoveryPrefs(); p.save(); Haptics.light(); dismiss(); onStart(p)
                    }
                    .font(.system(size: 12.5)).tint(CapTheme.mute)
                }
                .padding(.horizontal, 20).padding(.bottom, 12).background(.bar)
            }
        }
    }

    func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 10, weight: .heavy)).tracking(1.6).foregroundStyle(CapTheme.mute)
            content()
        }
    }

    func toggleRow(_ title: String, _ sub: String, _ binding: Binding<Bool>) -> some View {
        Button {
            binding.wrappedValue.toggle(); Haptics.select()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: binding.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20)).foregroundStyle(binding.wrappedValue ? CapTheme.red : CapTheme.line)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(CapTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(sub).font(.system(size: 12)).foregroundStyle(CapTheme.mute)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

/// Wrapping chip row for genres.
struct FlowChips: View {
    let items: [String]
    @Binding var selected: [String]
    var body: some View {
        let cols = [GridItem(.adaptive(minimum: 90), spacing: 8)]
        LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { g in
                let on = selected.contains(g)
                Button {
                    Haptics.select()
                    if on { selected.removeAll { $0 == g } } else { selected.append(g) }
                } label: {
                    Text(g).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                        .foregroundStyle(on ? .white : CapTheme.mute)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Capsule().fill(on ? CapTheme.red : CapTheme.bubble))
                        .overlay(Capsule().stroke(on ? Color.clear : CapTheme.line))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
