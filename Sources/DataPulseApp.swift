import SwiftUI

@main
struct DataPulseApp: App {
    @StateObject private var store = Store.shared
    @Environment(\.scenePhase) private var phase

    init() {
        Loc.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
        .onChange(of: phase) { newPhase in
            if newPhase == .active {
                Store.shared.refresh()
            }
        }
    }
}
