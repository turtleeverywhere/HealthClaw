import Foundation
import HealthKit
import UIKit
import CoreLocation
import WidgetKit

struct DailyMetric: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

@MainActor
class HealthKitManager: ObservableObject {
    private let store = HKHealthStore()

    @Published var isAuthorized = false
    @Published var todayActivity: ActivityData?
    @Published var todayHeart: HeartData?
    @Published var recentSleep: [SleepSession] = []
    @Published var recentWorkouts: [WorkoutSession] = []
    @Published var bodyData: BodyData?
    @Published var vitalsData: VitalsData?
    @Published var bodyBattery: Int?

    // Historical data for sparklines
    @Published var historicalWeight: [DailyMetric] = []
    @Published var historicalHRV: [DailyMetric] = []
    @Published var historicalRHR: [DailyMetric] = []
    @Published var historicalBodyFat: [DailyMetric] = []
    @Published var historicalSteps: [DailyMetric] = []

    // Workout route data
    @Published var workoutRoutes: [String: [CLLocationCoordinate2D]] = [:]
    private var hkWorkoutCache: [String: HKWorkout] = [:]

    // All quantity types we want to read
    private var quantityTypes: Set<HKQuantityType> {
        let ids: [HKQuantityTypeIdentifier] = [
            .stepCount, .distanceWalkingRunning, .distanceCycling,
            .activeEnergyBurned, .basalEnergyBurned, .appleExerciseTime,
            .flightsClimbed, .vo2Max, .walkingSpeed, .appleWalkingSteadiness,
            .heartRate, .restingHeartRate, .walkingHeartRateAverage,
            .heartRateVariabilitySDNN,
            .oxygenSaturation, .respiratoryRate, .bodyTemperature,
            .bloodPressureSystolic, .bloodPressureDiastolic,
            .bodyMass, .bodyMassIndex, .bodyFatPercentage, .height,
        ]
        return Set(ids.compactMap { HKQuantityType.quantityType(forIdentifier: $0) })
    }

    private var categoryTypes: Set<HKCategoryType> {
        let ids: [HKCategoryTypeIdentifier] = [
            .sleepAnalysis,
            .mindfulSession,
            .appleStandHour,
        ]
        return Set(ids.compactMap { HKCategoryType.categoryType(forIdentifier: $0) })
    }

    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        types.formUnion(quantityTypes)
        types.formUnion(categoryTypes)
        types.insert(HKObjectType.workoutType())
        types.insert(HKSeriesType.workoutRoute())
        if #available(iOS 18.0, *) {
            types.insert(HKObjectType.stateOfMindType())
        }
        return types
    }

    /// Quantity types the app requests WRITE permission for (dietary logging)
    private var writeTypes: Set<HKSampleType> {
        let ids: [HKQuantityTypeIdentifier] = [
            .dietaryEnergyConsumed,
            .dietaryProtein,
            .dietaryCarbohydrates,
            .dietaryFatTotal,
            .dietaryFatSaturated,
            .dietaryFiber,
            .dietarySugar,
            .dietarySodium,
            .dietaryCholesterol,
            .dietaryCalcium,
            .dietaryIron,
            .dietaryVitaminC,
            .dietaryVitaminD,
            .dietaryPotassium,
            .dietaryMagnesium,
            .dietaryVitaminA,
            .dietaryVitaminB6,
            .dietaryVitaminB12,
            .dietaryFolate,
            .dietaryZinc,
        ]
        return Set(ids.compactMap { HKQuantityType.quantityType(forIdentifier: $0) })
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            isAuthorized = true
        } catch {
            print("HealthKit auth error: \(error)")
        }
    }

    /// Read today's dietary totals from HealthKit (source of truth).
    func fetchDietaryTotals(for date: Date) async -> DailyNutritionSummary? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return nil }

        let kcal = await sumQuantity(.dietaryEnergyConsumed, unit: .kilocalorie(), from: start, to: end)
        let protein = await sumQuantity(.dietaryProtein, unit: .gram(), from: start, to: end)
        let carbs = await sumQuantity(.dietaryCarbohydrates, unit: .gram(), from: start, to: end)
        let fat = await sumQuantity(.dietaryFatTotal, unit: .gram(), from: start, to: end)

        // Count distinct dietary energy samples as meal count proxy
        let mealCount = await countSamples(.dietaryEnergyConsumed, from: start, to: end)

        let dateStr = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: date)
        }()

        return DailyNutritionSummary(
            date: dateStr,
            mealCount: mealCount,
            totalCalories: kcal,
            totalProteinG: protein,
            totalCarbsG: carbs,
            totalFatG: fat
        )
    }

    private func countSamples(_ identifier: HKQuantityTypeIdentifier, from start: Date, to end: Date) async -> Int {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: samples?.count ?? 0)
            }
            store.execute(query)
        }
    }

    /// Write a single dietary quantity sample to HealthKit.
    func writeDietarySample(
        identifier: HKQuantityTypeIdentifier,
        value: Double,
        unit: HKUnit,
        date: Date
    ) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else { return }
        let quantity = HKQuantity(unit: unit, doubleValue: value)
        let sample = HKQuantitySample(type: quantityType, quantity: quantity, start: date, end: date)
        try await store.save(sample)
    }

    // MARK: - Collect all data for a time range

    func collectData(from startDate: Date, to endDate: Date, sleepFrom: Date? = nil) async -> HealthSyncPayload {
        let sleepStart = sleepFrom ?? startDate
        async let activity = fetchActivity(from: startDate, to: endDate)
        async let heart = fetchHeart(from: startDate, to: endDate)
        async let sleep = fetchSleep(from: sleepStart, to: endDate)
        async let workouts = fetchWorkouts(from: startDate, to: endDate)
        async let body = fetchBody(from: startDate, to: endDate)
        async let vitals = fetchVitals(from: startDate, to: endDate)
        async let mindfulness = fetchMindfulness(from: startDate, to: endDate)
        async let mood = fetchMood(from: startDate, to: endDate)

        let activityData = await activity
        let heartData = await heart
        let sleepData = await sleep

        // Compute synthetic body battery (0-100)
        let battery = computeBodyBattery(hrv: heartData.hrvSdnn, sleepMin: sleepData.first?.totalDurationMin, steps: activityData.steps)

        return HealthSyncPayload(
            deviceId: UIDevice.current.name,
            syncedAt: Date(),
            periodFrom: startDate,
            periodTo: endDate,
            activity: activityData,
            heart: heartData,
            sleep: sleepData,
            workouts: await workouts,
            mood: await mood,
            body: await body,
            vitals: await vitals,
            mindfulness: await mindfulness,
            bodyBattery: battery
        )
    }

    // MARK: - Refresh dashboard data

    /// Convenience: refresh with today's data (used by Sleep/Workouts tabs)
    func refreshDashboard() async {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        await refreshData(from: startOfDay, to: now)
    }

    /// Refresh all data for a given date range
    func refreshData(from start: Date, to end: Date) async {
        let cal = Calendar.current
        let sleepFrom = cal.date(byAdding: .day, value: -1, to: start)!
        // Infrequent metrics need wider lookback
        let bodyLookback = cal.date(byAdding: .day, value: -90, to: end)!

        // Period data
        async let a = fetchActivity(from: start, to: end)
        async let h = fetchHeart(from: start, to: end)
        async let s = fetchSleep(from: sleepFrom, to: end)
        async let w = fetchWorkouts(from: start, to: end)
        async let b = fetchBody(from: bodyLookback, to: end)
        async let v = fetchVitals(from: bodyLookback, to: end)

        // Sparkline lookback: proportional to selected period, min 14 days
        let periodDays = max(cal.dateComponents([.day], from: start, to: end).day ?? 1, 1)
        let sparkDays = max(periodDays * 3, 14)
        let sparkStart = cal.date(byAdding: .day, value: -sparkDays, to: end)!

        async let hWeight = fetchDailySamples(.bodyMass, unit: .gramUnit(with: .kilo), from: sparkStart, to: end, options: .discreteAverage)
        async let hHRV = fetchDailySamples(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: sparkStart, to: end, options: .discreteAverage)
        async let hRHR = fetchDailySamples(.restingHeartRate, unit: HKUnit(from: "count/min"), from: sparkStart, to: end, options: .discreteAverage)
        async let hBF = fetchDailySamples(.bodyFatPercentage, unit: .percent(), from: sparkStart, to: end, options: .discreteAverage)
        async let hSteps = fetchDailySamples(.stepCount, unit: .count(), from: sparkStart, to: end, options: .cumulativeSum)

        todayActivity = await a
        todayHeart = await h
        // Filter sleep by wake-up date: only keep sessions ending within the requested range
        recentSleep = (await s).filter { $0.end >= start && $0.end <= end }
        recentWorkouts = await w
        bodyData = await b
        vitalsData = await v

        historicalWeight = await hWeight
        historicalHRV = await hHRV
        historicalRHR = await hRHR
        historicalBodyFat = (await hBF).map { DailyMetric(date: $0.date, value: $0.value * 100) }
        historicalSteps = await hSteps

        bodyBattery = computeBodyBattery(
            hrv: todayHeart?.hrvSdnn,
            sleepMin: recentSleep.first?.totalDurationMin,
            steps: todayActivity?.steps
        )

        cacheWidgetData()
    }

    private func cacheWidgetData() {
        let data = WidgetData(
            updatedAt: Date(),
            steps: todayActivity?.steps,
            activeCalories: todayActivity?.activeCalories,
            exerciseMinutes: todayActivity?.exerciseMinutes,
            distanceKm: todayActivity?.distanceKm,
            bodyBattery: bodyBattery,
            restingHR: todayHeart?.restingHr,
            hrv: todayHeart?.hrvSdnn,
            vo2Max: todayActivity?.vo2Max,
            sleepMinutes: recentSleep.first?.totalDurationMin,
            weightKg: bodyData?.weightKg,
            lastWorkoutType: recentWorkouts.first?.workoutType,
            lastWorkoutDurationMin: recentWorkouts.first?.durationMin
        )
        WidgetDataCache.save(data)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Activity

    private func fetchActivity(from start: Date, to end: Date) async -> ActivityData {
        var data = ActivityData()
        data.steps = Int(await sumQuantity(.stepCount, unit: .count(), from: start, to: end))
        let walkDist = await sumQuantity(.distanceWalkingRunning, unit: HKUnit.meter(), from: start, to: end) / 1000.0
        let cycleDist = await sumQuantity(.distanceCycling, unit: HKUnit.meter(), from: start, to: end) / 1000.0
        data.distanceKm = walkDist + cycleDist
        data.activeCalories = await sumQuantity(.activeEnergyBurned, unit: .kilocalorie(), from: start, to: end)
        data.basalCalories = await sumQuantity(.basalEnergyBurned, unit: .kilocalorie(), from: start, to: end)
        data.exerciseMinutes = await sumQuantity(.appleExerciseTime, unit: .minute(), from: start, to: end)
        data.flightsClimbed = Int(await sumQuantity(.flightsClimbed, unit: .count(), from: start, to: end))
        // VO2 Max updates infrequently — use wider lookback
        let vo2Start = Calendar.current.date(byAdding: .day, value: -90, to: end) ?? start
        data.vo2Max = await latestQuantity(.vo2Max, unit: HKUnit(from: "ml/kg*min"), from: vo2Start, to: end)
        let speedMs = await avgQuantity(.walkingSpeed, unit: HKUnit(from: "m/s"), from: start, to: end)
        data.walkingSpeedKmh = speedMs.map { $0 * 3.6 }
        return data
    }

    // MARK: - Heart

    private func fetchHeart(from start: Date, to end: Date) async -> HeartData {
        let bpmUnit = HKUnit(from: "count/min")
        var data = HeartData()
        data.restingHr = await latestQuantity(.restingHeartRate, unit: bpmUnit, from: start, to: end)
        data.avgHr = await avgQuantity(.heartRate, unit: bpmUnit, from: start, to: end)
        data.minHr = await minQuantity(.heartRate, unit: bpmUnit, from: start, to: end)
        data.maxHr = await maxQuantity(.heartRate, unit: bpmUnit, from: start, to: end)
        data.hrvSdnn = await latestQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), from: start, to: end)
        data.walkingHrAvg = await latestQuantity(.walkingHeartRateAverage, unit: bpmUnit, from: start, to: end)
        return data
    }

    // MARK: - Sleep

    private func fetchSleep(from start: Date, to end: Date) async -> [SleepSession] {
        let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: [])
                    return
                }

                // Group into sessions: samples within 30 min gap = same session
                var sessions: [SleepSession] = []
                var currentStages: [SleepStage] = []
                var sessionStart: Date?
                var lastEnd: Date?

                for sample in samples {
                    let value = HKCategoryValueSleepAnalysis(rawValue: sample.value)
                    let stageName: String
                    switch value {
                    case .asleepDeep: stageName = "deep"
                    case .asleepREM: stageName = "rem"
                    case .asleepCore: stageName = "core"
                    case .awake: stageName = "awake"
                    case .inBed: stageName = "in_bed"
                    default: stageName = "unknown"
                    }

                    if stageName == "in_bed" { continue }

                    let gap = lastEnd.map { sample.startDate.timeIntervalSince($0) } ?? 0
                    if gap > 1800, !currentStages.isEmpty, let sStart = sessionStart {
                        // Finalize previous session
                        let sEnd = lastEnd ?? sStart
                        let total = sEnd.timeIntervalSince(sStart) / 60.0
                        sessions.append(SleepSession(start: sStart, end: sEnd, totalDurationMin: total, stages: currentStages))
                        currentStages = []
                        sessionStart = nil
                    }

                    if sessionStart == nil { sessionStart = sample.startDate }
                    lastEnd = sample.endDate

                    let dur = sample.endDate.timeIntervalSince(sample.startDate) / 60.0
                    currentStages.append(SleepStage(stage: stageName, start: sample.startDate, end: sample.endDate, durationMin: dur))
                }

                // Finalize last session
                if !currentStages.isEmpty, let sStart = sessionStart {
                    let sEnd = lastEnd ?? sStart
                    let total = sEnd.timeIntervalSince(sStart) / 60.0
                    sessions.append(SleepSession(start: sStart, end: sEnd, totalDurationMin: total, stages: currentStages))
                }

                continuation.resume(returning: sessions)
            }
            store.execute(query)
        }
    }

    // MARK: - Workouts

    private func fetchWorkouts(from start: Date, to end: Date) async -> [WorkoutSession] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let (sessions, cache) = await withCheckedContinuation { (continuation: CheckedContinuation<([WorkoutSession], [String: HKWorkout]), Never>) in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 50, sortDescriptors: [sortDescriptor]) { _, samples, _ in
                guard let workouts = samples as? [HKWorkout] else {
                    continuation.resume(returning: ([], [:]))
                    return
                }

                var cacheMap: [String: HKWorkout] = [:]
                let sessions = workouts.map { w -> WorkoutSession in
                    let typeName = w.workoutActivityType.displayName
                    let dur = w.duration / 60.0
                    let dist = w.totalDistance.map { $0.doubleValue(for: .meter()) / 1000.0 }
                    let cal = w.totalEnergyBurned?.doubleValue(for: .kilocalorie())

                    let session = WorkoutSession(
                        workoutType: typeName,
                        start: w.startDate,
                        end: w.endDate,
                        durationMin: dur,
                        distanceKm: dist,
                        activeCalories: cal
                    )
                    cacheMap[session.id] = w
                    return session
                }
                continuation.resume(returning: (sessions, cacheMap))
            }
            self.store.execute(query)
        }

        hkWorkoutCache = cache
        return sessions
    }

    // MARK: - Workout Routes

    func loadRoute(for workout: WorkoutSession) async {
        // Skip if already loaded
        if workoutRoutes[workout.id] != nil { return }

        // Try cache first, otherwise re-query HealthKit for the workout
        var hkWorkout: HKWorkout? = hkWorkoutCache[workout.id]
        if hkWorkout == nil {
            hkWorkout = await findHKWorkout(matching: workout)
        }

        guard let hkWorkout else {
            workoutRoutes[workout.id] = []
            return
        }

        let routeType = HKSeriesType.workoutRoute()
        let pred = HKQuery.predicateForObjects(from: hkWorkout)

        let routes: [HKWorkoutRoute] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: routeType, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: (samples as? [HKWorkoutRoute]) ?? [])
            }
            self.store.execute(q)
        }

        guard let route = routes.first else {
            workoutRoutes[workout.id] = []
            return
        }

        let coords = await fetchRouteCoordinates(for: route)
        workoutRoutes[workout.id] = coords
    }

    private func findHKWorkout(matching workout: WorkoutSession) async -> HKWorkout? {
        let pred = HKQuery.predicateForSamples(withStart: workout.start, end: workout.end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: pred, limit: 5, sortDescriptors: [sort]) { _, samples, _ in
                let match = (samples as? [HKWorkout])?.first { w in
                    w.workoutActivityType.displayName == workout.workoutType
                }
                cont.resume(returning: match)
            }
            self.store.execute(q)
        }
    }

    private func fetchRouteCoordinates(for route: HKWorkoutRoute) async -> [CLLocationCoordinate2D] {
        final class Accumulator: @unchecked Sendable {
            var locations: [CLLocation] = []
        }
        let acc = Accumulator()

        return await withCheckedContinuation { cont in
            let query = HKWorkoutRouteQuery(route: route) { _, locs, done, _ in
                if let locs = locs {
                    acc.locations.append(contentsOf: locs)
                }
                if done {
                    cont.resume(returning: acc.locations.map { $0.coordinate })
                }
            }
            self.store.execute(query)
        }
    }

    // MARK: - Body

    private func fetchBody(from start: Date, to end: Date) async -> BodyData {
        var data = BodyData()
        data.weightKg = await latestQuantity(.bodyMass, unit: .gramUnit(with: .kilo), from: start, to: end)
        data.bmi = await latestQuantity(.bodyMassIndex, unit: .count(), from: start, to: end)
        data.bodyFatPct = await latestQuantity(.bodyFatPercentage, unit: .percent(), from: start, to: end).map { $0 * 100 }
        data.heightCm = await latestQuantity(.height, unit: .meterUnit(with: .centi), from: start, to: end)
        return data
    }

    // MARK: - Vitals

    private func fetchVitals(from start: Date, to end: Date) async -> VitalsData {
        var data = VitalsData()
        data.bloodPressureSystolic = await latestQuantity(.bloodPressureSystolic, unit: .millimeterOfMercury(), from: start, to: end)
        data.bloodPressureDiastolic = await latestQuantity(.bloodPressureDiastolic, unit: .millimeterOfMercury(), from: start, to: end)
        data.bloodOxygenPct = await latestQuantity(.oxygenSaturation, unit: .percent(), from: start, to: end).map { $0 * 100 }
        data.respiratoryRate = await latestQuantity(.respiratoryRate, unit: HKUnit(from: "count/min"), from: start, to: end)
        data.bodyTemperatureC = await latestQuantity(.bodyTemperature, unit: .degreeCelsius(), from: start, to: end)
        return data
    }

    // MARK: - Mindfulness

    private func fetchMindfulness(from start: Date, to end: Date) async -> [MindfulnessSession] {
        let type = HKCategoryType.categoryType(forIdentifier: .mindfulSession)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 50, sortDescriptors: nil) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample] else {
                    continuation.resume(returning: [])
                    return
                }
                let sessions = samples.map { s in
                    MindfulnessSession(start: s.startDate, end: s.endDate, durationMin: s.endDate.timeIntervalSince(s.startDate) / 60.0)
                }
                continuation.resume(returning: sessions)
            }
            store.execute(query)
        }
    }

    // MARK: - Mood (iOS 18+)

    private func fetchMood(from start: Date, to end: Date) async -> [MoodEntry] {
        guard #available(iOS 18.0, *) else { return [] }

        let type = HKObjectType.stateOfMindType()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 50, sortDescriptors: nil) { _, samples, _ in
                guard let minds = samples as? [HKStateOfMind] else {
                    continuation.resume(returning: [])
                    return
                }
                let entries = minds.map { m in
                    let kind = m.kind == .dailyMood ? "daily_mood" : "momentary_emotion"
                    let labels = m.labels.map { $0.rawValue.description }
                    let associations = m.associations.map { $0.rawValue.description }
                    return MoodEntry(kind: kind, timestamp: m.startDate, valence: m.valence, labels: labels, associations: associations)
                }
                continuation.resume(returning: entries)
            }
            store.execute(query)
        }
    }

    // MARK: - Body Battery (synthetic)

    private func computeBodyBattery(hrv: Double?, sleepMin: Double?, steps: Int?) -> Int? {
        // Simple heuristic: baseline 50, +/- based on HRV, sleep, activity
        var score: Double = 50

        if let hrv = hrv {
            // Higher HRV = better recovery. Average ~30-50ms for adults
            if hrv > 50 { score += 20 }
            else if hrv > 35 { score += 10 }
            else if hrv < 20 { score -= 15 }
        }

        if let sleep = sleepMin {
            // 7-9h optimal
            if sleep >= 420 && sleep <= 540 { score += 20 }
            else if sleep >= 360 { score += 10 }
            else if sleep < 300 { score -= 15 }
        }

        if let steps = steps {
            // Moderate activity boosts, extreme drains
            if steps > 5000 && steps < 15000 { score += 10 }
            else if steps > 20000 { score -= 10 }
        }

        return max(0, min(100, Int(score)))
    }

    // MARK: - Historical Daily Samples

    private func fetchDailySamples(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from startDate: Date, to endDate: Date, options: HKStatisticsOptions) async -> [DailyMetric] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }

        let anchorDate = Calendar.current.startOfDay(for: endDate)
        let interval = DateComponents(day: 1)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: anchorDate,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, results, _ in
                guard let results = results else {
                    continuation.resume(returning: [])
                    return
                }

                var metrics: [DailyMetric] = []
                results.enumerateStatistics(from: startDate, to: endDate) { stats, _ in
                    let value: Double?
                    if options.contains(.cumulativeSum) {
                        value = stats.sumQuantity()?.doubleValue(for: unit)
                    } else {
                        value = stats.averageQuantity()?.doubleValue(for: unit)
                    }
                    if let value = value, value > 0 {
                        metrics.append(DailyMetric(date: stats.startDate, value: value))
                    }
                }
                continuation.resume(returning: metrics)
            }

            self.store.execute(query)
        }
    }

    // MARK: - HealthKit Query Helpers

    private func sumQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
                continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(query)
        }
    }

    private func avgQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, result, _ in
                continuation.resume(returning: result?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func minQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteMin) { _, result, _ in
                continuation.resume(returning: result?.minimumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func maxQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteMax) { _, result, _ in
                continuation.resume(returning: result?.maximumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func latestQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }
}

// MARK: - Workout Type Display Names

extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .walking: return "Walking"
        case .swimming: return "Swimming"
        case .hiking: return "Hiking"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining: return "Strength Training"
        case .traditionalStrengthTraining: return "Strength Training"
        case .highIntensityIntervalTraining: return "HIIT"
        case .coreTraining: return "Core Training"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .stairClimbing: return "Stair Climbing"
        case .dance: return "Dance"
        case .cooldown: return "Cooldown"
        case .pilates: return "Pilates"
        case .crossTraining: return "Cross Training"
        case .tennis: return "Tennis"
        case .soccer: return "Soccer"
        case .basketball: return "Basketball"
        default: return "Other"
        }
    }
}
