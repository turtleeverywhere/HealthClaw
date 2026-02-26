import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var syncManager: SyncManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Sync status banner
                    SyncStatusBanner()

                    // Body Battery
                    if let battery = healthManager.bodyBattery {
                        BodyBatteryCard(level: battery)
                    }

                    // Activity ring-style card
                    if let activity = healthManager.todayActivity {
                        ActivityCard(activity: activity)
                    }

                    // Heart
                    if let heart = healthManager.todayHeart {
                        HeartCard(heart: heart)
                    }

                    // Sleep summary
                    if let sleep = healthManager.recentSleep.first {
                        SleepSummaryCard(session: sleep)
                    }

                    // Body
                    if let body = healthManager.bodyData, body.weightKg != nil {
                        BodyCard(body: body)
                    }

                    // Recent workout
                    if let workout = healthManager.recentWorkouts.first {
                        WorkoutCard(workout: workout)
                    }
                }
                .padding()
            }
            .navigationTitle("HealthBridge")
            .refreshable {
                await healthManager.refreshDashboard()
            }
            .task {
                await healthManager.refreshDashboard()
            }
        }
    }
}

// MARK: - Sync Status Banner

struct SyncStatusBanner: View {
    @EnvironmentObject var syncManager: SyncManager
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(syncManager.lastSyncStatus.rawValue)
                .font(.caption)
            Spacer()
            if let lastSync = settings.lastSyncDate {
                Text(lastSync, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !syncManager.isSyncing {
                Button("Sync Now") {
                    Task { await syncManager.performSync() }
                }
                .font(.caption)
                .buttonStyle(.bordered)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    var statusColor: Color {
        switch syncManager.lastSyncStatus {
        case .idle: return .gray
        case .syncing: return .blue
        case .success: return .green
        case .error: return .red
        }
    }
}

// MARK: - Body Battery Card

struct BodyBatteryCard: View {
    let level: Int

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "battery.100.bolt")
                    .foregroundStyle(batteryColor)
                Text("Body Battery")
                    .font(.headline)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline) {
                Text("\(level)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(batteryColor)
                Text("/ 100")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(level), total: 100)
                .tint(batteryColor)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    var batteryColor: Color {
        if level >= 70 { return .green }
        if level >= 40 { return .yellow }
        return .red
    }
}

// MARK: - Activity Card

struct ActivityCard: View {
    let activity: ActivityData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                Text("Activity")
                    .font(.headline)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricTile(icon: "figure.walk", label: "Steps", value: activity.steps.map { "\($0)" } ?? "-", color: .green)
                MetricTile(icon: "flame", label: "Calories", value: activity.activeCalories.map { String(format: "%.0f kcal", $0) } ?? "-", color: .orange)
                MetricTile(icon: "map", label: "Distance", value: activity.distanceKm.map { String(format: "%.1f km", $0) } ?? "-", color: .blue)
                MetricTile(icon: "timer", label: "Exercise", value: activity.exerciseMinutes.map { String(format: "%.0f min", $0) } ?? "-", color: .mint)
                MetricTile(icon: "arrow.up.right", label: "Flights", value: activity.flightsClimbed.map { "\($0)" } ?? "-", color: .purple)
                MetricTile(icon: "lungs", label: "VO₂ Max", value: activity.vo2Max.map { String(format: "%.1f", $0) } ?? "-", color: .cyan)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Heart Card

struct HeartCard: View {
    let heart: HeartData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Text("Heart")
                    .font(.headline)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricTile(icon: "heart", label: "Resting", value: heart.restingHr.map { String(format: "%.0f bpm", $0) } ?? "-", color: .red)
                MetricTile(icon: "heart.fill", label: "Avg", value: heart.avgHr.map { String(format: "%.0f bpm", $0) } ?? "-", color: .pink)
                MetricTile(icon: "waveform.path.ecg", label: "HRV", value: heart.hrvSdnn.map { String(format: "%.0f ms", $0) } ?? "-", color: .purple)
                MetricTile(icon: "figure.walk", label: "Walking", value: heart.walkingHrAvg.map { String(format: "%.0f bpm", $0) } ?? "-", color: .orange)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Sleep Summary Card

struct SleepSummaryCard: View {
    let session: SleepSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "moon.zzz.fill")
                    .foregroundStyle(.indigo)
                Text("Last Sleep")
                    .font(.headline)
                Spacer()
                Text(String(format: "%.1fh", session.totalDurationMin / 60.0))
                    .font(.title2.bold())
                    .foregroundStyle(.indigo)
            }

            // Stage breakdown
            let deep = session.stages.filter { $0.stage == "deep" }.reduce(0) { $0 + $1.durationMin }
            let rem = session.stages.filter { $0.stage == "rem" }.reduce(0) { $0 + $1.durationMin }
            let core = session.stages.filter { $0.stage == "core" }.reduce(0) { $0 + $1.durationMin }
            let awake = session.stages.filter { $0.stage == "awake" }.reduce(0) { $0 + $1.durationMin }

            HStack(spacing: 16) {
                SleepStagePill(label: "Deep", minutes: deep, color: .indigo)
                SleepStagePill(label: "REM", minutes: rem, color: .cyan)
                SleepStagePill(label: "Core", minutes: core, color: .blue)
                SleepStagePill(label: "Awake", minutes: awake, color: .gray)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct SleepStagePill: View {
    let label: String
    let minutes: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(String(format: "%.0fm", minutes))
                .font(.caption.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Body Card

struct BodyCard: View {
    let body: BodyData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "figure.stand")
                    .foregroundStyle(.teal)
                Text("Body")
                    .font(.headline)
            }
            HStack(spacing: 24) {
                if let w = self.body.weightKg {
                    VStack {
                        Text(String(format: "%.1f", w))
                            .font(.title2.bold())
                        Text("kg")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let bf = self.body.bodyFatPct {
                    VStack {
                        Text(String(format: "%.1f%%", bf))
                            .font(.title2.bold())
                        Text("Body Fat")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let bmi = self.body.bmi {
                    VStack {
                        Text(String(format: "%.1f", bmi))
                            .font(.title2.bold())
                        Text("BMI")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Workout Card

struct WorkoutCard: View {
    let workout: WorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "figure.run")
                    .foregroundStyle(.green)
                Text("Recent Workout")
                    .font(.headline)
            }
            Text(workout.workoutType)
                .font(.title3.bold())
            HStack(spacing: 16) {
                Label(String(format: "%.0f min", workout.durationMin), systemImage: "clock")
                if let dist = workout.distanceKm {
                    Label(String(format: "%.1f km", dist), systemImage: "map")
                }
                if let cal = workout.activeCalories {
                    Label(String(format: "%.0f kcal", cal), systemImage: "flame")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(workout.start, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Metric Tile

struct MetricTile: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)
            Text(value)
                .font(.subheadline.bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
