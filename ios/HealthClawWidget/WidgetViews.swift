import SwiftUI
import WidgetKit

// MARK: - Widget Definition

struct HealthClawWidget: Widget {
    let kind = "HealthClawWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HealthWidgetProvider()) { entry in
            WidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("HealthClaw")
        .description("Key health metrics at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Entry View

struct WidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: HealthEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(data: entry.data)
        case .systemMedium:
            MediumWidgetView(data: entry.data)
        case .systemLarge:
            LargeWidgetView(data: entry.data)
        default:
            SmallWidgetView(data: entry.data)
        }
    }
}

// MARK: - Small

struct SmallWidgetView: View {
    let data: WidgetData

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Text("HealthClaw")
                    .font(.caption2).bold()
                    .foregroundStyle(.secondary)
            }

            Spacer()

            MetricRow(icon: "figure.walk", color: .green,
                      label: "Steps", value: data.steps.map { "\(formatNumber($0))" } ?? "--")

            MetricRow(icon: "flame.fill", color: .orange,
                      label: "Calories", value: data.activeCalories.map { "\(Int($0))" } ?? "--")

            MetricRow(icon: "bolt.fill", color: batteryColor,
                      label: "Battery", value: data.bodyBattery.map { "\($0)%" } ?? "--")
        }
    }

    private var batteryColor: Color {
        guard let b = data.bodyBattery else { return .gray }
        if b >= 70 { return .green }
        if b >= 40 { return .yellow }
        return .red
    }
}

// MARK: - Medium

struct MediumWidgetView: View {
    let data: WidgetData

    var body: some View {
        HStack(spacing: 16) {
            // Left column
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                    Text("HealthClaw")
                        .font(.caption2).bold()
                        .foregroundStyle(.secondary)
                }

                Spacer()

                MetricRow(icon: "figure.walk", color: .green,
                          label: "Steps", value: data.steps.map { "\(formatNumber($0))" } ?? "--")

                MetricRow(icon: "flame.fill", color: .orange,
                          label: "Active Cal", value: data.activeCalories.map { "\(Int($0))" } ?? "--")

                MetricRow(icon: "figure.run", color: .cyan,
                          label: "Exercise", value: data.exerciseMinutes.map { "\(Int($0)) min" } ?? "--")
            }

            Divider()

            // Right column
            VStack(alignment: .leading, spacing: 6) {
                Spacer()

                MetricRow(icon: "heart.text.square", color: .pink,
                          label: "RHR", value: data.restingHR.map { "\(Int($0)) bpm" } ?? "--")

                MetricRow(icon: "waveform.path.ecg", color: .purple,
                          label: "HRV", value: data.hrv.map { "\(Int($0)) ms" } ?? "--")

                MetricRow(icon: "bolt.fill", color: batteryColor,
                          label: "Battery", value: data.bodyBattery.map { "\($0)%" } ?? "--")
            }
        }
    }

    private var batteryColor: Color {
        guard let b = data.bodyBattery else { return .gray }
        if b >= 70 { return .green }
        if b >= 40 { return .yellow }
        return .red
    }
}

// MARK: - Large

struct LargeWidgetView: View {
    let data: WidgetData

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Text("HealthClaw")
                    .font(.headline).bold()
                Spacer()
                if data.updatedAt != .distantPast {
                    Text(data.updatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Activity
            SectionHeader(title: "Activity")
            HStack(spacing: 16) {
                MetricTile(icon: "figure.walk", color: .green,
                           label: "Steps", value: data.steps.map { formatNumber($0) } ?? "--")
                MetricTile(icon: "flame.fill", color: .orange,
                           label: "Calories", value: data.activeCalories.map { "\(Int($0))" } ?? "--")
                MetricTile(icon: "figure.run", color: .cyan,
                           label: "Exercise", value: data.exerciseMinutes.map { "\(Int($0))m" } ?? "--")
                MetricTile(icon: "map", color: .blue,
                           label: "Distance", value: data.distanceKm.map { String(format: "%.1fkm", $0) } ?? "--")
            }

            Divider()

            // Heart & Recovery
            SectionHeader(title: "Heart & Recovery")
            HStack(spacing: 16) {
                MetricTile(icon: "heart.text.square", color: .pink,
                           label: "RHR", value: data.restingHR.map { "\(Int($0))" } ?? "--")
                MetricTile(icon: "waveform.path.ecg", color: .purple,
                           label: "HRV", value: data.hrv.map { "\(Int($0))ms" } ?? "--")
                MetricTile(icon: "lungs", color: .teal,
                           label: "VO2", value: data.vo2Max.map { String(format: "%.1f", $0) } ?? "--")
                MetricTile(icon: "bolt.fill", color: batteryColor,
                           label: "Battery", value: data.bodyBattery.map { "\($0)%" } ?? "--")
            }

            Divider()

            // Sleep & Weight
            HStack(spacing: 16) {
                if let sleep = data.sleepMinutes {
                    HStack(spacing: 6) {
                        Image(systemName: "bed.double.fill")
                            .foregroundStyle(.indigo)
                            .font(.caption)
                        VStack(alignment: .leading) {
                            Text("Sleep").font(.caption2).foregroundStyle(.secondary)
                            Text(formatSleep(sleep)).font(.subheadline).bold()
                        }
                    }
                }

                if let weight = data.weightKg {
                    HStack(spacing: 6) {
                        Image(systemName: "scalemass")
                            .foregroundStyle(.mint)
                            .font(.caption)
                        VStack(alignment: .leading) {
                            Text("Weight").font(.caption2).foregroundStyle(.secondary)
                            Text(String(format: "%.1f kg", weight)).font(.subheadline).bold()
                        }
                    }
                }

                if let wType = data.lastWorkoutType, let dur = data.lastWorkoutDurationMin {
                    HStack(spacing: 6) {
                        Image(systemName: "dumbbell")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                        VStack(alignment: .leading) {
                            Text(wType).font(.caption2).foregroundStyle(.secondary)
                            Text("\(Int(dur)) min").font(.subheadline).bold()
                        }
                    }
                }

                Spacer()
            }
        }
    }

    private var batteryColor: Color {
        guard let b = data.bodyBattery else { return .gray }
        if b >= 70 { return .green }
        if b >= 40 { return .yellow }
        return .red
    }

    private func formatSleep(_ min: Double) -> String {
        let h = Int(min) / 60
        let m = Int(min) % 60
        return "\(h)h \(m)m"
    }
}

// MARK: - Shared Components

struct MetricRow: View {
    let icon: String
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.caption)
                .frame(width: 14)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption).bold()
        }
    }
}

struct MetricTile: View {
    let icon: String
    let color: Color
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.caption)
            Text(value)
                .font(.caption).bold()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.caption).bold()
            .foregroundStyle(.secondary)
    }
}

private func formatNumber(_ n: Int) -> String {
    if n >= 1000 {
        let k = Double(n) / 1000.0
        return String(format: "%.1fk", k)
    }
    return "\(n)"
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    HealthClawWidget()
} timeline: {
    HealthEntry(date: .now, data: WidgetData(
        updatedAt: .now, steps: 8432, activeCalories: 342,
        exerciseMinutes: 45, bodyBattery: 72
    ))
}

#Preview("Medium", as: .systemMedium) {
    HealthClawWidget()
} timeline: {
    HealthEntry(date: .now, data: WidgetData(
        updatedAt: .now, steps: 8432, activeCalories: 342,
        exerciseMinutes: 45, bodyBattery: 72, restingHR: 58, hrv: 42
    ))
}

#Preview("Large", as: .systemLarge) {
    HealthClawWidget()
} timeline: {
    HealthEntry(date: .now, data: WidgetData(
        updatedAt: .now, steps: 8432, activeCalories: 342,
        exerciseMinutes: 45, distanceKm: 6.2, bodyBattery: 72,
        restingHR: 58, hrv: 42, vo2Max: 44.2,
        sleepMinutes: 438, weightKg: 78.5,
        lastWorkoutType: "Running", lastWorkoutDurationMin: 32
    ))
}
