import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

            WorkoutsView()
                .tabItem {
                    Label("Fitness", systemImage: "figure.run")
                }

            SleepView()
                .tabItem {
                    Label("Sleep", systemImage: "moon.zzz.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .tint(.white)
    }
}
