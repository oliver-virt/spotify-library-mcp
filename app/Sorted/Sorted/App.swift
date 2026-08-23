import SwiftUI

@main
struct SortedApp: App {
    @StateObject var model = LibraryModel()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: LibraryModel
    var body: some View {
        NavigationStack {
            switch model.stage {
            case .welcome, .scanning: ScanView()
            case .report: ReportView()
            case .plan: PlanView()
            case .applying, .done: ApplyView()
            }
        }
        .tint(Color(red: 0.83, green: 0.39, blue: 0.10))
    }
}
