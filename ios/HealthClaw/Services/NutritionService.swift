import Foundation
import HealthKit

// MARK: - Nutrition Service Errors

enum NutritionServiceError: LocalizedError {
    case notConfigured
    case invalidResponse(Int)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "API endpoint and key must be configured in Settings."
        case .invalidResponse(let code):
            return "Server returned HTTP \(code)."
        case .decodingError(let error):
            return "Failed to parse server response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Nutrition Service

final class NutritionService {

    private let settings: AppSettings
    private let healthStore = HKHealthStore()

    // ISO 8601 decoder that handles fractional seconds
    private lazy var decoder: JSONDecoder = {
        let d = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = formatter.date(from: str) { return date }
            // fallback without fractional seconds
            let fallback = ISO8601DateFormatter()
            if let date = fallback.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot parse date: \(str)"
            )
        }
        return d
    }()

    init(settings: AppSettings) {
        self.settings = settings
    }

    // MARK: - Analyze Food

    /// POST /api/nutrition/analyze
    func analyzeFood(text: String, imageData: Data?) async throws -> NutritionAnalysisResult {
        guard settings.isConfigured else { throw NutritionServiceError.notConfigured }

        let url = URL(string: "\(settings.baseURL)/api/nutrition/analyze")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(settings.apiKey, forHTTPHeaderField: "X-API-Key")

        var body: [String: Any] = ["text": text]
        if let imageData {
            body["image_base64"] = imageData.base64EncodedString()
            body["image_mime_type"] = "image/jpeg"
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NutritionServiceError.invalidResponse(0)
        }
        guard (200...299).contains(http.statusCode) else {
            throw NutritionServiceError.invalidResponse(http.statusCode)
        }

        do {
            return try decoder.decode(NutritionAnalysisResult.self, from: data)
        } catch {
            throw NutritionServiceError.decodingError(error)
        }
    }

    // MARK: - Fetch History

    /// GET /api/nutrition/history?days=N
    func fetchHistory(days: Int) async throws -> [NutritionAnalysisResult] {
        guard settings.isConfigured else { throw NutritionServiceError.notConfigured }

        var components = URLComponents(string: "\(settings.baseURL)/api/nutrition/history")!
        components.queryItems = [URLQueryItem(name: "days", value: "\(days)")]
        var request = URLRequest(url: components.url!)
        request.setValue(settings.apiKey, forHTTPHeaderField: "X-API-Key")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw NutritionServiceError.invalidResponse(code)
        }

        do {
            return try decoder.decode([NutritionAnalysisResult].self, from: data)
        } catch {
            throw NutritionServiceError.decodingError(error)
        }
    }

    // MARK: - Fetch Daily Summary

    /// GET /api/nutrition/summary?date=YYYY-MM-DD
    func fetchDailySummary(date: Date) async throws -> DailyNutritionSummary {
        guard settings.isConfigured else { throw NutritionServiceError.notConfigured }

        let dateStr = isoDateString(from: date)
        var components = URLComponents(string: "\(settings.baseURL)/api/nutrition/summary")!
        components.queryItems = [URLQueryItem(name: "date", value: dateStr)]
        var request = URLRequest(url: components.url!)
        request.setValue(settings.apiKey, forHTTPHeaderField: "X-API-Key")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw NutritionServiceError.invalidResponse(code)
        }

        do {
            return try decoder.decode(DailyNutritionSummary.self, from: data)
        } catch {
            throw NutritionServiceError.decodingError(error)
        }
    }

    // MARK: - Write HealthKit Samples

    /// Write all healthkit_samples into HealthKit. Returns saved sample UUIDs.
    func writeHealthKitSamples(from result: NutritionAnalysisResult) async throws -> [UUID] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }

        var savedUUIDs: [UUID] = []
        for sample in result.healthkitSamples {
            guard let (typeId, expectedUnit) = Self.identifierMap[sample.identifier],
                  let quantityType = HKQuantityType.quantityType(forIdentifier: typeId) else {
                continue
            }

            // Skip samples where the server unit is incompatible (e.g. IU for mass-type nutrients)
            let serverUnit = sample.unit.lowercased()
            let isMassType = expectedUnit != .kilocalorie()
            if isMassType && (serverUnit == "iu") { continue }

            let quantity = HKQuantity(unit: expectedUnit, doubleValue: sample.value)
            let hkSample = HKQuantitySample(
                type: quantityType,
                quantity: quantity,
                start: result.timestamp,
                end: result.timestamp
            )

            try await healthStore.save(hkSample)
            savedUUIDs.append(hkSample.uuid)
        }
        return savedUUIDs
    }

    // MARK: - Delete HealthKit Samples

    /// Delete previously saved HK samples by their UUIDs.
    func deleteHealthKitSamples(uuids: [UUID]) async throws {
        guard HKHealthStore.isHealthDataAvailable(), !uuids.isEmpty else { return }

        let predicate = HKQuery.predicateForObjects(with: Set(uuids))
        try await deleteDietarySamples(matching: predicate)
    }

    /// Delete all dietary HK samples at a specific timestamp (fallback for history meals without tracked UUIDs).
    func deleteHealthKitSamples(at timestamp: Date) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        // Match samples whose start date is exactly this timestamp (±1s tolerance)
        let from = timestamp.addingTimeInterval(-1)
        let to = timestamp.addingTimeInterval(1)
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
        try await deleteDietarySamples(matching: predicate)
    }

    /// Delete dietary samples matching a predicate across all dietary types.
    private func deleteDietarySamples(matching predicate: NSPredicate) async throws {
        for (_, (typeId, _)) in Self.identifierMap {
            guard let quantityType = HKQuantityType.quantityType(forIdentifier: typeId) else { continue }

            let samples: [HKSample] = await withCheckedContinuation { cont in
                let query = HKSampleQuery(
                    sampleType: quantityType,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: nil
                ) { _, results, _ in
                    cont.resume(returning: results ?? [])
                }
                healthStore.execute(query)
            }

            if !samples.isEmpty {
                try await healthStore.delete(samples)
            }
        }
    }

    // MARK: - Server identifier → HKQuantityTypeIdentifier

    /// Maps server identifier → (HK type, correct HK unit).
    /// Using fixed units avoids crashes from incompatible units (e.g. IU for mass types).
    static let identifierMap: [String: (HKQuantityTypeIdentifier, HKUnit)] = [
        "dietaryEnergyConsumed": (.dietaryEnergyConsumed, .kilocalorie()),
        "dietaryProtein":        (.dietaryProtein, .gram()),
        "dietaryCarbohydrates":  (.dietaryCarbohydrates, .gram()),
        "dietaryFatTotal":       (.dietaryFatTotal, .gram()),
        "dietaryFatSaturated":   (.dietaryFatSaturated, .gram()),
        "dietaryFiber":          (.dietaryFiber, .gram()),
        "dietarySugar":          (.dietarySugar, .gram()),
        "dietarySodium":         (.dietarySodium, .gramUnit(with: .milli)),
        "dietaryCholesterol":    (.dietaryCholesterol, .gramUnit(with: .milli)),
        "dietaryCalcium":        (.dietaryCalcium, .gramUnit(with: .milli)),
        "dietaryIron":           (.dietaryIron, .gramUnit(with: .milli)),
        "dietaryVitaminC":       (.dietaryVitaminC, .gramUnit(with: .milli)),
        "dietaryVitaminD":       (.dietaryVitaminD, .gramUnit(with: .micro)),
        "dietaryPotassium":      (.dietaryPotassium, .gramUnit(with: .milli)),
        "dietaryMagnesium":      (.dietaryMagnesium, .gramUnit(with: .milli)),
        "dietaryVitaminA":       (.dietaryVitaminA, .gramUnit(with: .micro)),
        "dietaryVitaminB6":      (.dietaryVitaminB6, .gramUnit(with: .milli)),
        "dietaryVitaminB12":     (.dietaryVitaminB12, .gramUnit(with: .micro)),
        "dietaryFolate":         (.dietaryFolate, .gramUnit(with: .micro)),
        "dietaryZinc":           (.dietaryZinc, .gramUnit(with: .milli)),
    ]

    // MARK: - Helpers

    private func isoDateString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: date)
    }

    private func hkUnit(from string: String) -> HKUnit? {
        switch string.lowercased() {
        case "kcal", "kilocalorie", "kilocalories":
            return .kilocalorie()
        case "g", "gram", "grams":
            return .gram()
        case "mg", "milligram", "milligrams":
            return HKUnit.gramUnit(with: .milli)
        case "mcg", "microgram", "micrograms":
            return HKUnit.gramUnit(with: .micro)
        case "ml", "milliliter", "milliliters":
            return HKUnit.literUnit(with: .milli)
        case "iu":
            return .internationalUnit()
        default:
            return nil
        }
    }
}
