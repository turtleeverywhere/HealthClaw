import Foundation

// MARK: - Sync Payload (mirrors server models)

struct HealthSyncPayload: Codable {
    let deviceId: String
    let syncedAt: Date
    let periodFrom: Date
    let periodTo: Date
    var activity: ActivityData?
    var heart: HeartData?
    var sleep: [SleepSession] = []
    var workouts: [WorkoutSession] = []
    var mood: [MoodEntry] = []
    var body: BodyData?
    var vitals: VitalsData?
    var mindfulness: [MindfulnessSession] = []
    var bodyBattery: Int?

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case syncedAt = "synced_at"
        case periodFrom = "period_from"
        case periodTo = "period_to"
        case activity, heart, sleep, workouts, mood, body, vitals, mindfulness
        case bodyBattery = "body_battery"
    }
}

struct ActivityData: Codable {
    var steps: Int?
    var distanceKm: Double?
    var activeCalories: Double?
    var basalCalories: Double?
    var exerciseMinutes: Double?
    var standHours: Int?
    var flightsClimbed: Int?
    var vo2Max: Double?
    var walkingSpeedKmh: Double?
    var walkingSteadiness: Double?

    enum CodingKeys: String, CodingKey {
        case steps
        case distanceKm = "distance_km"
        case activeCalories = "active_calories"
        case basalCalories = "basal_calories"
        case exerciseMinutes = "exercise_minutes"
        case standHours = "stand_hours"
        case flightsClimbed = "flights_climbed"
        case vo2Max = "vo2_max"
        case walkingSpeedKmh = "walking_speed_kmh"
        case walkingSteadiness = "walking_steadiness"
    }
}

struct HeartData: Codable {
    var restingHr: Double?
    var avgHr: Double?
    var minHr: Double?
    var maxHr: Double?
    var hrvSdnn: Double?
    var walkingHrAvg: Double?

    enum CodingKeys: String, CodingKey {
        case restingHr = "resting_hr"
        case avgHr = "avg_hr"
        case minHr = "min_hr"
        case maxHr = "max_hr"
        case hrvSdnn = "hrv_sdnn"
        case walkingHrAvg = "walking_hr_avg"
    }
}

struct SleepStage: Codable {
    let stage: String
    let start: Date
    let end: Date
    let durationMin: Double

    enum CodingKeys: String, CodingKey {
        case stage, start, end
        case durationMin = "duration_min"
    }
}

struct SleepSession: Codable {
    let start: Date
    let end: Date
    let totalDurationMin: Double
    var stages: [SleepStage] = []
    var inBedDurationMin: Double?

    enum CodingKeys: String, CodingKey {
        case start, end, stages
        case totalDurationMin = "total_duration_min"
        case inBedDurationMin = "in_bed_duration_min"
    }
}

struct WorkoutSession: Codable, Identifiable {
    var id: String { "\(workoutType)-\(start.timeIntervalSince1970)" }

    let workoutType: String
    let start: Date
    let end: Date
    let durationMin: Double
    var distanceKm: Double?
    var activeCalories: Double?
    var avgHr: Double?
    var maxHr: Double?
    var elevationGainM: Double?

    enum CodingKeys: String, CodingKey {
        case workoutType = "workout_type"
        case start, end
        case durationMin = "duration_min"
        case distanceKm = "distance_km"
        case activeCalories = "active_calories"
        case avgHr = "avg_hr"
        case maxHr = "max_hr"
        case elevationGainM = "elevation_gain_m"
    }
}

struct MoodEntry: Codable, Identifiable {
    var id: String { "\(kind)-\(timestamp.timeIntervalSince1970)" }

    let kind: String
    let timestamp: Date
    let valence: Double
    var labels: [String] = []
    var associations: [String] = []
}

struct BodyData: Codable {
    var weightKg: Double?
    var bmi: Double?
    var bodyFatPct: Double?
    var heightCm: Double?

    enum CodingKeys: String, CodingKey {
        case weightKg = "weight_kg"
        case bmi
        case bodyFatPct = "body_fat_pct"
        case heightCm = "height_cm"
    }
}

struct VitalsData: Codable {
    var bloodPressureSystolic: Double?
    var bloodPressureDiastolic: Double?
    var bloodOxygenPct: Double?
    var respiratoryRate: Double?
    var bodyTemperatureC: Double?

    enum CodingKeys: String, CodingKey {
        case bloodPressureSystolic = "blood_pressure_systolic"
        case bloodPressureDiastolic = "blood_pressure_diastolic"
        case bloodOxygenPct = "blood_oxygen_pct"
        case respiratoryRate = "respiratory_rate"
        case bodyTemperatureC = "body_temperature_c"
    }
}

struct MindfulnessSession: Codable {
    let start: Date
    let end: Date
    let durationMin: Double

    enum CodingKeys: String, CodingKey {
        case start, end
        case durationMin = "duration_min"
    }
}
