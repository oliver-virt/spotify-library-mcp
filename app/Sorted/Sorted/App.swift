import SwiftUI

@main
struct SortedApp: App {
    @StateObject var model = LibraryModel()
    @StateObject var ent = Entitlements()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model).environmentObject(ent)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: LibraryModel
    @AppStorage("dacapo.hasScanned") var hasScanned = false
    var body: some View {
        Group {
            if model.stage == .main {
                TabView {
                    NavigationStack { ReportView() }
                        .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
                    NavigationStack { PlaylistsTab() }
                        .tabItem { Label("Playlists", systemImage: "music.note.list") }
                }
            } else {
                NavigationStack { ScanView() }
            }
        }
        .task {
            // returning user: skip the welcome screen, rescan silently (local + fast)
            if hasScanned && model.stage == .welcome { await model.scan() }
        }
        .onChange(of: model.stage) { _, st in if st == .main { hasScanned = true } }
        .tint(Color(red: 0.83, green: 0.39, blue: 0.10))
    }
}
