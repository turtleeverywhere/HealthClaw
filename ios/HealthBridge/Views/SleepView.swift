import SwiftUI

struct SleepView: View {
    @EnvironmentObject var healthManager: HealthKitManager

    var body: some View {
        NavigationStack {
            List {
                if healthManager.recentSleep.isEmpty {
                    ContentUnavailableView("No Sleep Data", systemImage: "bed.double", description: Text("Sleep sessions will appear here"))
                } else {
                    ForEach(Array(healthManager.recentSleep.enumerated()), id: \.offset) { _, session in
                        SleepRow(session: session)
                    }
                }
            }
            .navigationTitle("Sleep")
            .refreshable {
                await healthManager.refreshDashboard()
            }
        }
    }
}

struct SleepRow: View {
    let session: SleepSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.start, format: .dateTime.weekday(.wide).month().day())
                    .font(.headline)
                Spacer()
                Text(String(format: "%.1fh", session.totalDurationMin / 60.0))
                    .font(.title3.bold())
                    .foregroundStyle(.indigo)
            }
            HStack {
                Text("\(session.start, format: .dateTime.hour().minute()) → \(session.end, format: .dateTime.hour().minute())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Stage bar
            let total = session.totalDurationMin
            if total > 0 {
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        ForEach(Array(session.stages.enumerated()), id: \.offset) { _, stage in
                            Rectangle()
                                .fill(stageColor(stage.stage))
                                .frame(width: max(2, geo.size.width * stage.durationMin / total))
                        }
                    }
                }
                .frame(height: 12)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // Legend
            HStack(spacing: 12) {
                StageLegend(label: "Deep", color: .indigo)
                StageLegend(label: "REM", color: .cyan)
                StageLegend(label: "Core", color: .blue)
                StageLegend(label: "Awake", color: .gray)
            }
            .font(.caption2)
        }
        .padding(.vertical, 4)
    }

    func stageColor(_ stage: String) -> Color {
        switch stage {
        case "deep": return .indigo
        case "rem": return .cyan
        case "core": return .blue
        case "awake": return .gray
        default: return .secondary
        }
    }
}

struct StageLegend: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).foregroundStyle(.secondary)
        }
    }
}
