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
        .tint(Color(red: 0.83, green: 0.39, blue: 0.10))
    }
}
