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

    /// Write all healthkit_samples from an analysis result into HealthKit.
    func writeHealthKitSamples(from result: NutritionAnalysisResult) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        for sample in result.healthkitSamples {
            let typeId = HKQuantityTypeIdentifier(rawValue: sample.identifier)
            guard let quantityType = HKQuantityType.quantityType(forIdentifier: typeId) else {
                continue
            }

            let unit = hkUnit(from: sample.unit)
            let quantity = HKQuantity(unit: unit, doubleValue: sample.value)
            let hkSample = HKQuantitySample(
                type: quantityType,
                quantity: quantity,
                start: result.timestamp,
                end: result.timestamp
            )

            try await healthStore.save(hkSample)
        }
    }

    // MARK: - Helpers

    private func isoDateString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f.string(from: date)
    }

    private func hkUnit(from string: String) -> HKUnit {
        // Map common server-side unit strings to HKUnit
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
        default:
            // Attempt to parse directly as an HKUnit string
            return HKUnit(from: string)
        }
    }
}
