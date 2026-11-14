import SwiftUI
import BackgroundTasks

@main
struct DataPulseApp: App {
    @StateObject private var store = Store.shared
    @Environment(\.scenePhase) private var phase

    init() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.datapulse.refresh", using: nil) { task in
            DispatchQueue.main.async {
                Store.shared.tick { task.setTaskCompleted(success: true) }
                Scheduler.schedule()
            }
        }
        Loc.shared.start()
        Scheduler.schedule()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
        .onChange(of: phase) { _ in
            store.tick()
            Scheduler.schedule()
        }
    }
}
