import SwiftUI

struct WorkoutsView: View {
    @EnvironmentObject var healthManager: HealthKitManager

    var body: some View {
        NavigationStack {
            List {
                if healthManager.recentWorkouts.isEmpty {
                    ContentUnavailableView("No Workouts", systemImage: "figure.run", description: Text("Recent workouts will appear here"))
                } else {
                    ForEach(healthManager.recentWorkouts) { workout in
                        WorkoutRow(workout: workout)
                    }
                }
            }
            .navigationTitle("Workouts")
            .refreshable {
                await healthManager.refreshDashboard()
            }
        }
    }
}

struct WorkoutRow: View {
    let workout: WorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(workout.workoutType)
                    .font(.headline)
                Spacer()
                Text(workout.start, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                Label(String(format: "%.0f min", workout.durationMin), systemImage: "clock")
                if let dist = workout.distanceKm {
                    Label(String(format: "%.2f km", dist), systemImage: "map")
                }
                if let cal = workout.activeCalories {
                    Label(String(format: "%.0f kcal", cal), systemImage: "flame.fill")
                }
                if let hr = workout.avgHr {
                    Label(String(format: "%.0f bpm", hr), systemImage: "heart.fill")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
