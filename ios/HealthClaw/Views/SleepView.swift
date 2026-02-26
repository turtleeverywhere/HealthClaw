import SwiftUI

struct SleepView: View {
    @EnvironmentObject var healthManager: HealthKitManager

    var body: some View {
        NavigationStack {
            ScrollView {
                if healthManager.recentSleep.isEmpty {
                    ContentUnavailableView("No Sleep Data", systemImage: "bed.double", description: Text("Sleep sessions will appear here"))
                        .padding(.top, 60)
                } else {
                    VStack(spacing: 12) {
                        ForEach(Array(healthManager.recentSleep.enumerated()), id: \.offset) { _, session in
                            SleepRow(session: session)
                        }
                    }
                    .padding()
                }
            }
            .background(Color.appBackground.ignoresSafeArea())
            .scrollContentBackground(.hidden)
            .navigationTitle("Sleep")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .refreshable {
                await healthManager.refreshDashboard()
            }
        }
    }
}

struct SleepRow: View {
    let session: SleepSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(session.start, format: .dateTime.weekday(.wide).month().day())
                    .font(.headline)
                Spacer()
                let hours = session.totalDurationMin / 60.0
                Text(String(format: "%.0fh %02.0fm", hours.rounded(.down), session.totalDurationMin.truncatingRemainder(dividingBy: 60)))
                    .font(.title3.bold())
                    .foregroundStyle(.indigo)
            }

            HStack {
                Text("\(session.start, format: .dateTime.hour().minute()) \u{2192} \(session.end, format: .dateTime.hour().minute())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Stage bar
            let total = session.totalDurationMin
            if total > 0 {
                let stageFractions = session.stages.map { (stage: $0.stage, fraction: $0.durationMin / total) }
                SleepStageBar(stages: stageFractions)
                    .frame(height: 12)
            }

            // Stage breakdown
            let deep = session.stages.filter { $0.stage == "deep" }.reduce(0) { $0 + $1.durationMin }
            let rem = session.stages.filter { $0.stage == "rem" }.reduce(0) { $0 + $1.durationMin }
            let core = session.stages.filter { $0.stage == "core" }.reduce(0) { $0 + $1.durationMin }
            let awake = session.stages.filter { $0.stage == "awake" }.reduce(0) { $0 + $1.durationMin }

            HStack(spacing: 16) {
                StageLegendItem(label: "Deep", minutes: deep, color: .indigo)
                StageLegendItem(label: "REM", minutes: rem, color: .cyan)
                StageLegendItem(label: "Core", minutes: core, color: .blue)
                StageLegendItem(label: "Awake", minutes: awake, color: .gray)
            }
            .font(.caption2)
        }
        .cardStyle()
    }
}

struct StageLegendItem: View {
    let label: String
    let minutes: Double
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(label) \(String(format: "%.0fm", minutes))")
                .foregroundStyle(.secondary)
        }
    }
}
