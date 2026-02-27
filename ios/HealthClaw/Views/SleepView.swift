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
                            SleepDetailCard(session: session)
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

// MARK: - Sleep Detail Card

struct SleepDetailCard: View {
    let session: SleepSession

    private var deep: Double { stageMin("deep") }
    private var rem: Double { stageMin("rem") }
    private var core: Double { stageMin("core") }
    private var awake: Double { stageMin("awake") }
    private var asleepMin: Double { deep + rem + core }
    private var inBedMin: Double { session.inBedDurationMin ?? session.totalDurationMin }
    private var efficiency: Double { inBedMin > 0 ? (asleepMin / inBedMin) * 100 : 0 }

    private var sleepScore: Int {
        var score = 0.0

        // Duration score (0-35): 7-9h ideal
        let hrs = asleepMin / 60.0
        if hrs >= 7 && hrs <= 9 { score += 35 }
        else if hrs >= 6 && hrs < 7 { score += 25 }
        else if hrs > 9 && hrs <= 10 { score += 25 }
        else if hrs >= 5 { score += 15 }
        else { score += 5 }

        // Deep % score (0-25): 13-23% ideal
        let deepPct = asleepMin > 0 ? deep / asleepMin * 100 : 0
        if deepPct >= 13 && deepPct <= 23 { score += 25 }
        else if deepPct >= 8 && deepPct < 13 { score += 18 }
        else if deepPct > 23 && deepPct <= 30 { score += 18 }
        else { score += 8 }

        // REM % score (0-25): 20-25% ideal
        let remPct = asleepMin > 0 ? rem / asleepMin * 100 : 0
        if remPct >= 20 && remPct <= 25 { score += 25 }
        else if remPct >= 15 && remPct < 20 { score += 18 }
        else if remPct > 25 && remPct <= 35 { score += 18 }
        else { score += 8 }

        // Efficiency score (0-15): >90% ideal
        if efficiency >= 90 { score += 15 }
        else if efficiency >= 85 { score += 12 }
        else if efficiency >= 80 { score += 8 }
        else { score += 3 }

        return min(100, Int(score))
    }

    private var scoreColor: Color {
        if sleepScore >= 80 { return .green }
        if sleepScore >= 60 { return .yellow }
        return .orange
    }

    private var scoreLabel: String {
        if sleepScore >= 85 { return "Excellent" }
        if sleepScore >= 70 { return "Good" }
        if sleepScore >= 55 { return "Fair" }
        return "Poor"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header: date + score
            headerSection

            // Duration + bedtime/wake
            durationSection

            // Stage timeline
            if session.totalDurationMin > 0 {
                stageTimeline
            }

            // Stage breakdown with % and ranges
            stageBreakdown

            // Metrics row
            metricsRow
        }
        .cardStyle()
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.end, format: .dateTime.weekday(.wide).month().day())
                    .font(.headline)
                Text("Bedtime \(session.start, format: .dateTime.hour().minute()) \u{2192} Wake \(session.end, format: .dateTime.hour().minute())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 2) {
                Text("\(sleepScore)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor)
                Text(scoreLabel)
                    .font(.caption2.bold())
                    .foregroundStyle(scoreColor)
            }
            .frame(width: 64, height: 64)
            .background(scoreColor.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Duration

    @ViewBuilder
    private var durationSection: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            let hours = session.totalDurationMin / 60.0
            Text(String(format: "%.0fh %02.0fm", hours.rounded(.down), session.totalDurationMin.truncatingRemainder(dividingBy: 60)))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.indigo)
            Text("asleep")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Stage Timeline

    @ViewBuilder
    private var stageTimeline: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sleep Stages")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            // Timeline bar with time-proportional widths
            GeometryReader { geo in
                let totalSpan = session.end.timeIntervalSince(session.start)
                if totalSpan > 0 {
                    HStack(spacing: 0.5) {
                        ForEach(Array(session.stages.enumerated()), id: \.offset) { _, stage in
                            let fraction = stage.durationMin * 60.0 / totalSpan
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(stageColor(stage.stage))
                                .frame(width: max(1, geo.size.width * fraction), height: stageHeight(stage.stage))
                                .frame(height: 32, alignment: .bottom)
                        }
                    }
                }
            }
            .frame(height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // Time axis
            HStack {
                Text(session.start, format: .dateTime.hour().minute())
                Spacer()
                let mid = Date(timeIntervalSince1970: (session.start.timeIntervalSince1970 + session.end.timeIntervalSince1970) / 2)
                Text(mid, format: .dateTime.hour().minute())
                Spacer()
                Text(session.end, format: .dateTime.hour().minute())
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Stage Breakdown

    @ViewBuilder
    private var stageBreakdown: some View {
        VStack(spacing: 8) {
            stageRow(label: "Deep", minutes: deep, color: .indigo, idealRange: "13–23%")
            stageRow(label: "REM", minutes: rem, color: .cyan, idealRange: "20–25%")
            stageRow(label: "Core", minutes: core, color: .blue, idealRange: "45–55%")
            stageRow(label: "Awake", minutes: awake, color: .gray, idealRange: "<5%")
        }
    }

    @ViewBuilder
    private func stageRow(label: String, minutes: Double, color: Color, idealRange: String) -> some View {
        let pct = asleepMin > 0 ? minutes / (asleepMin + awake) * 100 : 0
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.caption.bold())
                .frame(width: 40, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: max(0, geo.size.width * min(pct / 100, 1.0)))
                }
            }
            .frame(height: 8)
            Text(String(format: "%.0fm", minutes))
                .font(.caption.bold())
                .frame(width: 36, alignment: .trailing)
            Text(String(format: "%.0f%%", pct))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
    }

    // MARK: - Metrics Row

    @ViewBuilder
    private var metricsRow: some View {
        HStack(spacing: 0) {
            sleepMetric(icon: "gauge.with.dots.needle.33percent", label: "Efficiency", value: String(format: "%.0f%%", efficiency), color: efficiency >= 85 ? .green : .yellow)
            Spacer()
            sleepMetric(icon: "bed.double.fill", label: "In Bed", value: formatDuration(inBedMin), color: .indigo)
            Spacer()
            sleepMetric(icon: "moon.fill", label: "Asleep", value: formatDuration(asleepMin), color: .blue)
            Spacer()
            sleepMetric(icon: "eye.fill", label: "Awake", value: formatDuration(awake), color: .gray)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func sleepMetric(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.callout)
            Text(value)
                .font(.caption.bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func stageMin(_ stage: String) -> Double {
        session.stages.filter { $0.stage == stage }.reduce(0) { $0 + $1.durationMin }
    }

    private func stageColor(_ stage: String) -> Color {
        switch stage {
        case "deep": return .indigo
        case "rem": return .cyan
        case "core": return .blue
        case "awake": return Color.gray.opacity(0.5)
        default: return .secondary
        }
    }

    private func stageHeight(_ stage: String) -> CGFloat {
        switch stage {
        case "deep": return 32
        case "core": return 22
        case "rem": return 14
        case "awake": return 6
        default: return 16
        }
    }

    private func formatDuration(_ minutes: Double) -> String {
        let h = Int(minutes) / 60
        let m = Int(minutes) % 60
        return h > 0 ? String(format: "%dh %02dm", h, m) : String(format: "%dm", m)
    }
}

// MARK: - Stage Legend (kept for dashboard use)

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
