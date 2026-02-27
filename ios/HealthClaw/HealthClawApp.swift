import SwiftUI

@main
struct HealthClawApp: App {
    @StateObject private var healthManager = HealthKitManager()
    @StateObject private var syncManager = SyncManager()
    @StateObject private var settings = AppSettings()
    @StateObject private var nutritionManager = NutritionManager()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(healthManager)
                .environmentObject(syncManager)
                .environmentObject(settings)
                .environmentObject(nutritionManager)
                .preferredColorScheme(.dark)
                .task {
                    await healthManager.requestAuthorization()
                    syncManager.configure(healthManager: healthManager, settings: settings)
                    nutritionManager.configure(settings: settings, healthManager: healthManager)
                    await syncManager.syncIfNeeded()
                }
        }
    }
}
