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
    @EnvironmentObject var ent: Entitlements
    @AppStorage("dacapo.hasScanned") var hasScanned = false
    var body: some View {
        Group {
            if model.stage == .main {
                ChatView()
            } else {
                NavigationStack { ScanView() }
            }
        }
        .task { await ent.start() }
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
