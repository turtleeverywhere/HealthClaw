import Foundation

// MARK: - Chat Message

struct NutritionChatMessage: Identifiable, Codable {
    let id: UUID
    let role: MessageRole
    let text: String
    var imageData: Data?
    let timestamp: Date
    var analysisResult: NutritionAnalysisResult?

    enum MessageRole: String, Codable {
        case user, assistant
    }

    init(
        id: UUID = UUID(),
        role: MessageRole,
        text: String,
        imageData: Data? = nil,
        timestamp: Date = Date(),
        analysisResult: NutritionAnalysisResult? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.imageData = imageData
        self.timestamp = timestamp
        self.analysisResult = analysisResult
    }
}

// MARK: - Server Response

struct NutritionAnalysisResult: Codable, Identifiable {
    var id: String { "\(mealId)" }
    let mealId: Int
    let timestamp: Date
    let description: String
    let foodItems: [FoodItem]
    let totals: NutrientTotals
    let healthkitSamples: [HealthKitSample]

    enum CodingKeys: String, CodingKey {
        case mealId = "meal_id"
        case timestamp, description
        case foodItems = "food_items"
        case totals
        case healthkitSamples = "healthkit_samples"
    }
}

// MARK: - Food Item

struct FoodItem: Codable, Identifiable {
    var id: String { name }
    let name: String
    let portion: String
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let fiberG: Double?
    let sugarG: Double?
    let sodiumMg: Double?

    enum CodingKeys: String, CodingKey {
        case name, portion, calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case sugarG = "sugar_g"
        case sodiumMg = "sodium_mg"
    }
}

// MARK: - Nutrient Totals

struct NutrientTotals: Codable {
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let fiberG: Double?
    let sugarG: Double?
    let sodiumMg: Double?

    enum CodingKeys: String, CodingKey {
        case calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case sugarG = "sugar_g"
        case sodiumMg = "sodium_mg"
    }
}

// MARK: - HealthKit Sample

struct HealthKitSample: Codable {
    let identifier: String
    let value: Double
    let unit: String
}

// MARK: - Daily Summary

struct DailyNutritionSummary: Codable {
    let date: String
    let mealCount: Int
    let totalCalories: Double
    let totalProteinG: Double
    let totalCarbsG: Double
    let totalFatG: Double

    enum CodingKeys: String, CodingKey {
        case date
        case mealCount = "meal_count"
        case totalCalories = "total_calories"
        case totalProteinG = "total_protein_g"
        case totalCarbsG = "total_carbs_g"
        case totalFatG = "total_fat_g"
    }
}
