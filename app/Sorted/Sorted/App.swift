import SwiftUI

@main
struct SortedApp: App {
    @StateObject var model = LibraryModel()
    @StateObject var ent = Entitlements()
    @StateObject var router = Router()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model).environmentObject(ent).environmentObject(router)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: LibraryModel
    @EnvironmentObject var ent: Entitlements
    @EnvironmentObject var router: Router
    @AppStorage("dacapo.hasScanned") var hasScanned = false
    var body: some View {
        Group {
            if model.stage == .main {
                TabView(selection: $router.tab) {
                    ChatView()
                        .tabItem { Label("Cap", systemImage: "message.fill") }.tag(0)
                    JobsView()
                        .tabItem { Label("Jobs", systemImage: "square.grid.2x2.fill") }.tag(1)
                    FilesTab()
                        .tabItem { Label("Files", systemImage: "archivebox.fill") }.tag(2)
                }
                .preferredColorScheme(.dark)
            } else {
                NavigationStack { ScanView() }
            }
        }
        .task { await ent.start() }
        .task { if ProcessInfo.processInfo.environment["DACAPO_DIAG"] != nil { await Diag.runProbe() } }
        .task {
            #if targetEnvironment(simulator)
            if ProcessInfo.processInfo.environment["DACAPO_DEMO"] != nil { model.seedDemo(); return }
            #endif
            // returning user: skip the welcome screen, rescan silently (local + fast)
            if hasScanned && model.stage == .welcome { await model.scan() }
        }
        .onChange(of: model.stage) { _, st in if st == .main { hasScanned = true } }
        .tint(Color(red: 0.91, green: 0.27, blue: 0.11))
    }
}
