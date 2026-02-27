import SwiftUI
import CoreLocation

// MARK: - View Period

enum ViewPeriod: String, CaseIterable {
    case day = "Day"
    case week = "Week"
    case month = "Month"

    func dateRange(around date: Date) -> (start: Date, end: Date) {
        let cal = Calendar.current
        switch self {
        case .day:
            let start = cal.startOfDay(for: date)
            let end = min(cal.date(byAdding: .day, value: 1, to: start)!, Date())
            return (start, end)
        case .week:
            var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            let start = cal.date(from: comps) ?? cal.startOfDay(for: date)
            let end = min(cal.date(byAdding: .day, value: 7, to: start)!, Date())
            return (start, end)
        case .month:
            let start = cal.date(from: cal.dateComponents([.year, .month], from: date))!
            let end = min(cal.date(byAdding: .month, value: 1, to: start)!, Date())
            return (start, end)
        }
    }

    func offset(_ date: Date, by direction: Int) -> Date {
        let cal = Calendar.current
        switch self {
        case .day: return cal.date(byAdding: .day, value: direction, to: date)!
        case .week: return cal.date(byAdding: .weekOfYear, value: direction, to: date)!
        case .month: return cal.date(byAdding: .month, value: direction, to: date)!
        }
    }

    func label(for date: Date) -> String {
        let cal = Calendar.current
        let fmt = DateFormatter()
        switch self {
        case .day:
            if cal.isDateInToday(date) { return "Today" }
            if cal.isDateInYesterday(date) { return "Yesterday" }
            fmt.dateFormat = "MMM d, yyyy"
            return fmt.string(from: date)
        case .week:
            let range = dateRange(around: date)
            fmt.dateFormat = "MMM d"
            let startStr = fmt.string(from: range.start)
            fmt.dateFormat = "MMM d, yyyy"
            let endStr = fmt.string(from: cal.date(byAdding: .day, value: -1, to: min(range.end, Date())) ?? range.end)
            return "\(startStr) – \(endStr)"
        case .month:
            fmt.dateFormat = "MMMM yyyy"
            return fmt.string(from: date)
        }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @EnvironmentObject var healthManager: HealthKitManager
    @EnvironmentObject var syncManager: SyncManager
    @State private var selectedPeriod: ViewPeriod = .day
    @State private var selectedDate: Date = Date()
    @State private var isLoading = false

    private var dateRange: (start: Date, end: Date) {
        selectedPeriod.dateRange(around: selectedDate)
    }

    private var canGoForward: Bool {
        selectedPeriod.offset(selectedDate, by: 1) <= Date()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Period selector
                    PeriodSelectorView(
                        period: $selectedPeriod,
                        date: $selectedDate,
                        canGoForward: canGoForward
                    )

                    SyncStatusBanner()

                    if isLoading {
                        ProgressView()
                            .padding(40)
                    } else {
                        dashboardContent
                    }
                }
                .padding()
            }
            .background(Color.appBackground.ignoresSafeArea())
            .scrollContentBackground(.hidden)
            .navigationTitle("HealthClaw")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .refreshable { await refresh() }
            .task { await refresh() }
            .onChange(of: selectedPeriod) { _, _ in Task { await refresh() } }
            .onChange(of: selectedDate) { _, _ in Task { await refresh() } }
        }
    }

    private func refresh() async {
        isLoading = true
        let range = dateRange
        await healthManager.refreshData(from: range.start, to: range.end)
        isLoading = false
    }

    @ViewBuilder
    private var dashboardContent: some View {
        // Body Battery — only for today
        if selectedPeriod == .day, Calendar.current.isDateInToday(selectedDate),
           let battery = healthManager.bodyBattery {
            BodyBatteryCard(level: battery)
        }

        SectionHeader(title: "Biology")

        if let activity = healthManager.todayActivity, let vo2 = activity.vo2Max {
            VO2MaxCard(value: vo2)
        }

        HStack(spacing: 12) {
            if let hrv = healthManager.todayHeart?.hrvSdnn {
                HRVCard(value: hrv, history: healthManager.historicalHRV.map(\.value))
            }
            if let rhr = healthManager.todayHeart?.restingHr {
                RHRCard(value: rhr, history: healthManager.historicalRHR.map(\.value))
            }
        }

        if let w = healthManager.bodyData?.weightKg {
            WeightCard(value: w, history: healthManager.historicalWeight.map(\.value))
        }

        HStack(spacing: 12) {
            if let bf = healthManager.bodyData?.bodyFatPct {
                BodyFatCard(value: bf, history: healthManager.historicalBodyFat.map(\.value))
            }
            if let bmi = healthManager.bodyData?.bmi {
                BMICard(value: bmi)
            }
        }

        if let vitals = healthManager.vitalsData,
           vitals.bloodOxygenPct != nil || vitals.respiratoryRate != nil {
            VitalsCard(vitals: vitals)
        }

        SectionHeader(title: "Activity")

        if let activity = healthManager.todayActivity {
            ActivityCard(activity: activity, stepHistory: healthManager.historicalSteps.map(\.value))
        }

        SectionHeader(title: "Sleep")

        if healthManager.recentSleep.isEmpty {
            Text("No sleep data for this period")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding()
        } else {
            CollapsibleList(
                items: healthManager.recentSleep,
                previewCount: selectedPeriod == .day ? .max : 3,
                id: { "\($1.start.timeIntervalSince1970)" }
            ) { _, session in
                SleepSummaryCard(session: session)
            }
        }

        if !healthManager.recentWorkouts.isEmpty {
            SectionHeader(title: "Workouts")
            CollapsibleList(
                items: Array(healthManager.recentWorkouts),
                previewCount: selectedPeriod == .day ? .max : 3,
                id: { $1.id }
            ) { _, workout in
                WorkoutCard(workout: workout)
            }
        }
    }
}

// MARK: - Period Selector

struct PeriodSelectorView: View {
    @Binding var period: ViewPeriod
    @Binding var date: Date
    let canGoForward: Bool

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    var body: some View {
        VStack(spacing: 10) {
            Picker("Period", selection: $period) {
                ForEach(ViewPeriod.allCases, id: \.self) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Button { date = period.offset(date, by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.bold())
                        .foregroundStyle(.white)
                }
                Spacer()
                Text(period.label(for: date))
                    .font(.subheadline.bold())
                if !isToday {
                    Button { date = Date() } label: {
                        Text("Today")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.blue.opacity(0.3))
                            .clipShape(Capsule())
                    }
                }
                Spacer()
                Button { date = period.offset(date, by: 1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.bold())
                        .foregroundStyle(canGoForward ? .white : .white.opacity(0.2))
                }
                .disabled(!canGoForward)
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Collapsible List

struct CollapsibleList<Item, Content: View>: View {
    let items: [Item]
    let previewCount: Int
    let id: (Int, Item) -> String
    @ViewBuilder let content: (Int, Item) -> Content
    @State private var expanded = false

    private var shouldCollapse: Bool { previewCount < items.count }
    private var visibleItems: [(offset: Int, element: Item)] {
        let slice = expanded ? items : Array(items.prefix(previewCount))
        return Array(slice.enumerated())
    }

    var body: some View {
        ForEach(visibleItems, id: \.offset) { idx, item in
            content(idx, item)
        }
        if shouldCollapse {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { expanded.toggle() }
            } label: {
                HStack {
                    Text(expanded ? "Show less" : "Show all \(items.count)")
                        .font(.caption.bold())
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title2.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
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
                .foregroundStyle(.secondary)
            Spacer()
            if let lastSync = settings.lastSyncDate {
                Text(lastSync, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            if !syncManager.isSyncing {
                Button("Sync") {
                    Task { await syncManager.performSync() }
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .tint(.blue)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.cardBorder, lineWidth: 0.5))
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
        HStack(spacing: 20) {
            CircularGaugeView(value: Double(level), color: batteryColor)
                .frame(width: 110, height: 110)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "battery.100.bolt")
                        .foregroundStyle(batteryColor)
                    Text("Body Battery")
                        .font(.headline)
                }
                Text(statusText)
                    .font(.subheadline.bold())
                    .foregroundStyle(batteryColor)
                Text("Based on HRV, sleep & activity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .cardStyle()
    }

    var batteryColor: Color {
        if level >= 70 { return .green }
        if level >= 40 { return .yellow }
        return .red
    }

    var statusText: String {
        if level >= 80 { return "Fully Charged" }
        if level >= 60 { return "Good" }
        if level >= 40 { return "Moderate" }
        if level >= 20 { return "Low" }
        return "Depleted"
    }
}

// MARK: - VO2 Max Card

struct VO2MaxCard: View {
    let value: Double

    private let ranges: [(min: Double, max: Double)] = [
        (0, 25), (25, 35), (35, 45), (45, 55), (55, 70)
    ]

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "lungs.fill")
                        .foregroundStyle(.cyan)
                    Text("VO\u{2082} Max")
                        .font(.headline)
                }
                Text(String(format: "%.1f", value))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                statusLabel
            }

            Spacer()

            RangeIndicatorView(value: value, ranges: ranges, activeColor: .cyan)
                .frame(width: 120, height: 80)
        }
        .cardStyle()
    }

    var statusLabel: some View {
        let status: (String, Color) = {
            if value >= 50 { return ("Excellent", .green) }
            if value >= 40 { return ("Good", .cyan) }
            if value >= 30 { return ("Fair", .yellow) }
            return ("Low", .orange)
        }()
        return Text(status.0)
            .font(.subheadline.bold())
            .foregroundStyle(status.1)
    }
}

// MARK: - HRV Card

struct HRVCard: View {
    let value: Double
    let history: [Double]

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(.purple)
                    .font(.caption)
                Text("HRV")
                    .font(.subheadline.bold())
            }

            if history.count >= 2 {
                SparklineView(data: history, color: .purple)
                    .frame(height: 50)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%.1f", value))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("ms")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if history.count >= 2 {
                TrendLabel(data: history)
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }
}

// MARK: - RHR Card

struct RHRCard: View {
    let value: Double
    let history: [Double]

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                Text("RHR")
                    .font(.subheadline.bold())
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%.0f", value))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("bpm")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            rhrStatus

            SemiGaugeView(value: value, minValue: 35, maxValue: 100)
                .frame(height: 50)
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    var rhrStatus: some View {
        let status: (String, Color) = {
            if value < 50 { return ("Excellent", .green) }
            if value < 65 { return ("Good", .cyan) }
            if value < 80 { return ("Average", .yellow) }
            return ("High", .orange)
        }()
        return Text(status.0)
            .font(.caption.bold())
            .foregroundStyle(status.1)
    }
}

// MARK: - Weight Card

struct WeightCard: View {
    let value: Double
    let history: [Double]

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "scalemass.fill")
                    .foregroundStyle(.teal)
                Text("Weight")
                    .font(.headline)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", value))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text("kg")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if history.count >= 2 {
                SparklineView(data: history, color: .teal)
                    .frame(height: 60)
            }
            if history.count >= 2 {
                TrendLabel(data: history)
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }
}

// MARK: - Body Fat Card

struct BodyFatCard: View {
    let value: Double
    let history: [Double]

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "percent")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text("Body Fat")
                    .font(.subheadline.bold())
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%.1f", value))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            bfStatus

            SemiGaugeView(value: value, minValue: 5, maxValue: 40)
                .frame(height: 50)
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    var bfStatus: some View {
        let status: (String, Color) = {
            if value < 14 { return ("Athletic", .green) }
            if value < 20 { return ("Fit", .cyan) }
            if value < 25 { return ("Average", .yellow) }
            return ("Above Avg", .orange)
        }()
        return Text(status.0)
            .font(.caption.bold())
            .foregroundStyle(status.1)
    }
}

// MARK: - BMI Card

struct BMICard: View {
    let value: Double

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "figure.stand")
                    .foregroundStyle(.mint)
                    .font(.caption)
                Text("BMI")
                    .font(.subheadline.bold())
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%.1f", value))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
            }

            bmiStatus

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    var bmiStatus: some View {
        let status: (String, Color) = {
            if value < 18.5 { return ("Underweight", .orange) }
            if value < 25 { return ("Normal", .green) }
            if value < 30 { return ("Overweight", .yellow) }
            return ("Obese", .red)
        }()
        return Text(status.0)
            .font(.caption.bold())
            .foregroundStyle(status.1)
    }
}

// MARK: - Vitals Card

struct VitalsCard: View {
    let vitals: VitalsData

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "heart.text.square.fill")
                    .foregroundStyle(.pink)
                Text("Vitals")
                    .font(.headline)
            }

            HStack(spacing: 12) {
                if let spo2 = vitals.bloodOxygenPct {
                    VitalTile(icon: "lungs.fill", label: "SpO\u{2082}", value: String(format: "%.0f%%", spo2), color: .cyan)
                }
                if let rr = vitals.respiratoryRate {
                    VitalTile(icon: "wind", label: "Resp Rate", value: String(format: "%.0f /min", rr), color: .mint)
                }
                if let temp = vitals.bodyTemperatureC {
                    VitalTile(icon: "thermometer.medium", label: "Temp", value: String(format: "%.1f\u{00B0}C", temp), color: .orange)
                }
                if let sys = vitals.bloodPressureSystolic, let dia = vitals.bloodPressureDiastolic {
                    VitalTile(icon: "heart.circle", label: "BP", value: "\(Int(sys))/\(Int(dia))", color: .red)
                }
            }
        }
        .cardStyle()
    }
}

struct VitalTile: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
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

// MARK: - Activity Card

struct ActivityCard: View {
    let activity: ActivityData
    let stepHistory: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                Text("Activity Summary")
                    .font(.headline)
            }

            // Step sparkline
            if stepHistory.count >= 2 {
                SparklineView(data: stepHistory, color: .green)
                    .frame(height: 50)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ActivityMetric(icon: "figure.walk", label: "Steps", value: activity.steps.map { formatNumber($0) } ?? "-", color: .green)
                ActivityMetric(icon: "flame", label: "Active Cal", value: activity.activeCalories.map { String(format: "%.0f", $0) } ?? "-", color: .orange)
                ActivityMetric(icon: "map", label: "Distance", value: activity.distanceKm.map { String(format: "%.1f km", $0) } ?? "-", color: .blue)
                ActivityMetric(icon: "timer", label: "Exercise", value: activity.exerciseMinutes.map { String(format: "%.0f min", $0) } ?? "-", color: .mint)
                ActivityMetric(icon: "arrow.up.right", label: "Flights", value: activity.flightsClimbed.map { "\($0)" } ?? "-", color: .purple)
                ActivityMetric(icon: "figure.walk.motion", label: "Speed", value: activity.walkingSpeedKmh.map { String(format: "%.1f km/h", $0) } ?? "-", color: .cyan)
            }
        }
        .cardStyle()
    }

    func formatNumber(_ n: Int) -> String {
        if n >= 1000 {
            return String(format: "%.1fk", Double(n) / 1000.0)
        }
        return "\(n)"
    }
}

struct ActivityMetric: View {
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
    }
}

// MARK: - Sleep Summary Card

struct SleepSummaryCard: View {
    let session: SleepSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "moon.zzz.fill")
                        .foregroundStyle(.indigo)
                    Text("Last Sleep")
                        .font(.headline)
                }
                Spacer()
                Text(session.start, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                let hours = session.totalDurationMin / 60.0
                Text(String(format: "%.0fh %02.0fm", hours.rounded(.down), session.totalDurationMin.truncatingRemainder(dividingBy: 60)))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.indigo)
                Text("total")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Stage bar
            let total = session.totalDurationMin
            if total > 0 {
                let stageFractions = session.stages.map { (stage: $0.stage, fraction: $0.durationMin / total) }
                SleepStageBar(stages: stageFractions)
            }

            // Stage breakdown pills
            let deep = session.stages.filter { $0.stage == "deep" }.reduce(0) { $0 + $1.durationMin }
            let rem = session.stages.filter { $0.stage == "rem" }.reduce(0) { $0 + $1.durationMin }
            let core = session.stages.filter { $0.stage == "core" }.reduce(0) { $0 + $1.durationMin }
            let awake = session.stages.filter { $0.stage == "awake" }.reduce(0) { $0 + $1.durationMin }

            HStack(spacing: 0) {
                SleepStagePill(label: "Deep", minutes: deep, color: .indigo)
                Spacer()
                SleepStagePill(label: "REM", minutes: rem, color: .cyan)
                Spacer()
                SleepStagePill(label: "Core", minutes: core, color: .blue)
                Spacer()
                SleepStagePill(label: "Awake", minutes: awake, color: .gray)
            }
        }
        .cardStyle()
    }
}

struct SleepStagePill: View {
    let label: String
    let minutes: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(String(format: "%.0fm", minutes))
                .font(.caption.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Workout Card

struct WorkoutCard: View {
    let workout: WorkoutSession
    @EnvironmentObject var healthManager: HealthKitManager

    private var routeCoords: [CLLocationCoordinate2D]? {
        healthManager.workoutRoutes[workout.id]
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(workoutColor.opacity(0.2))
                        .frame(width: 44, height: 44)
                    Image(systemName: workoutIcon)
                        .foregroundStyle(workoutColor)
                        .font(.title3)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.workoutType)
                        .font(.subheadline.bold())
                    HStack(spacing: 12) {
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
                }

                Spacer()

                Text(workout.start, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.4))
            }

            // Route map
            if let coords = routeCoords, coords.count >= 2 {
                WorkoutMapView(coordinates: coords, height: 140)
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

// MARK: - Metric Tile (kept for compatibility)

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
