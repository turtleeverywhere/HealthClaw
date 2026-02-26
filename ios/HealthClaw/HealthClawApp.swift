import SwiftUI

@main
struct HealthClawApp: App {
    @StateObject private var healthManager = HealthKitManager()
    @StateObject private var syncManager = SyncManager()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(healthManager)
                .environmentObject(syncManager)
                .environmentObject(settings)
                .preferredColorScheme(.dark)
                .task {
                    await healthManager.requestAuthorization()
                    syncManager.configure(healthManager: healthManager, settings: settings)
                    await syncManager.syncIfNeeded()
                }
        }
    }
}
