import Foundation

struct WidgetData: Codable {
    var updatedAt: Date
    var steps: Int?
    var activeCalories: Double?
    var exerciseMinutes: Double?
    var distanceKm: Double?
    var bodyBattery: Int?
    var restingHR: Double?
    var hrv: Double?
    var vo2Max: Double?
    var sleepMinutes: Double?
    var weightKg: Double?
    var lastWorkoutType: String?
    var lastWorkoutDurationMin: Double?

    static let empty = WidgetData(updatedAt: .distantPast)
}

enum WidgetDataCache {
    static let appGroupID = "group.com.flyingturtle.healthclaw"
    private static let key = "widget_data"

    static func save(_ data: WidgetData) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        if let encoded = try? JSONEncoder().encode(data) {
            defaults.set(encoded, forKey: key)
        }
    }

    static func load() -> WidgetData {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(WidgetData.self, from: data)
        else { return .empty }
        return decoded
    }
}
