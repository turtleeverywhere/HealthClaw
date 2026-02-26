import SwiftUI
import CoreLocation

struct WorkoutsView: View {
    @EnvironmentObject var healthManager: HealthKitManager

    var body: some View {
        NavigationStack {
            ScrollView {
                if healthManager.recentWorkouts.isEmpty {
                    ContentUnavailableView("No Workouts", systemImage: "figure.run", description: Text("Recent workouts will appear here"))
                        .padding(.top, 60)
                } else {
                    VStack(spacing: 12) {
                        ForEach(healthManager.recentWorkouts) { workout in
                            WorkoutDetailRow(workout: workout)
                        }
                    }
                    .padding()
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .scrollContentBackground(.hidden)
            .navigationTitle("Workouts")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .refreshable {
                await healthManager.refreshDashboard()
            }
        }
    }
}

struct WorkoutDetailRow: View {
    let workout: WorkoutSession
    @EnvironmentObject var healthManager: HealthKitManager

    private var routeCoords: [CLLocationCoordinate2D]? {
        healthManager.workoutRoutes[workout.id]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(workoutColor.opacity(0.2))
                        .frame(width: 40, height: 40)
                    Image(systemName: workoutIcon)
                        .foregroundStyle(workoutColor)
                        .font(.body)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.workoutType)
                        .font(.headline)
                    Text(workout.start, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(String(format: "%.0f min", workout.durationMin))
                    .font(.title3.bold())
                    .foregroundStyle(workoutColor)
            }

            // Route map
            if let coords = routeCoords, coords.count >= 2 {
                WorkoutMapView(coordinates: coords, height: 180)
            }

            // Stats grid
            HStack(spacing: 0) {
                if let dist = workout.distanceKm {
                    WorkoutStat(label: "Distance", value: String(format: "%.2f km", dist), icon: "map")
                    Spacer()
                }
                if let cal = workout.activeCalories {
                    WorkoutStat(label: "Calories", value: String(format: "%.0f kcal", cal), icon: "flame.fill")
                    Spacer()
                }
                if let hr = workout.avgHr {
                    WorkoutStat(label: "Avg HR", value: String(format: "%.0f bpm", hr), icon: "heart.fill")
                    Spacer()
                }
                if let maxHr = workout.maxHr {
                    WorkoutStat(label: "Max HR", value: String(format: "%.0f bpm", maxHr), icon: "heart.fill")
                }
            }
        }
        .cardStyle()
        .task {
            await healthManager.loadRoute(for: workout)
        }
    }

    var workoutIcon: String {
        switch workout.workoutType.lowercased() {
        case let t where t.contains("run"): return "figure.run"
        case let t where t.contains("cycling"), let t where t.contains("bike"): return "figure.outdoor.cycle"
        case let t where t.contains("swim"): return "figure.pool.swim"
        case let t where t.contains("walk"): return "figure.walk"
        case let t where t.contains("hik"): return "figure.hiking"
        case let t where t.contains("yoga"): return "figure.yoga"
        case let t where t.contains("strength"): return "dumbbell.fill"
        case let t where t.contains("hiit"): return "bolt.heart.fill"
        default: return "figure.mixed.cardio"
        }
    }

    var workoutColor: Color {
        switch workout.workoutType.lowercased() {
        case let t where t.contains("run"): return .green
        case let t where t.contains("cycling"), let t where t.contains("bike"): return .orange
        case let t where t.contains("swim"): return .cyan
        case let t where t.contains("strength"): return .purple
        case let t where t.contains("hiit"): return .red
        case let t where t.contains("yoga"): return .mint
        default: return .blue
        }
    }
}

struct WorkoutStat: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
