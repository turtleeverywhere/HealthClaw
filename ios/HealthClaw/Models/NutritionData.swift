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

struct NutritionAnalysisResult: Codable, Identifiable, Hashable {
    static func == (lhs: NutritionAnalysisResult, rhs: NutritionAnalysisResult) -> Bool {
        lhs.mealId == rhs.mealId
    }
    func hash(into hasher: inout Hasher) { hasher.combine(mealId) }

    var id: String { "\(mealId)" }
    var mealId: Int
    var timestamp: Date
    var description: String
    var foodItems: [FoodItem]
    var totals: NutrientTotals
    var healthkitSamples: [HealthKitSample]
    /// UUIDs of HKSamples written to HealthKit for this meal
    var savedHKSampleUUIDs: [UUID]

    enum CodingKeys: String, CodingKey {
        case mealId = "meal_id"
        case timestamp, description
        case foodItems = "food_items"
        case totals
        case healthkitSamples = "healthkit_samples"
        case savedHKSampleUUIDs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mealId = try c.decode(Int.self, forKey: .mealId)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        description = try c.decode(String.self, forKey: .description)
        foodItems = try c.decode([FoodItem].self, forKey: .foodItems)
        totals = try c.decode(NutrientTotals.self, forKey: .totals)
        healthkitSamples = try c.decode([HealthKitSample].self, forKey: .healthkitSamples)
        savedHKSampleUUIDs = (try? c.decodeIfPresent([UUID].self, forKey: .savedHKSampleUUIDs)) ?? []
    }

    /// Recalculate totals and healthkit_samples from current foodItems.
    mutating func recalculate() {
        let cal = foodItems.reduce(0.0) { $0 + $1.calories }
        let pro = foodItems.reduce(0.0) { $0 + $1.proteinG }
        let carb = foodItems.reduce(0.0) { $0 + $1.carbsG }
        let fat = foodItems.reduce(0.0) { $0 + $1.fatG }
        let fib: Double? = foodItems.contains(where: { $0.fiberG != nil })
            ? foodItems.reduce(0.0) { $0 + ($1.fiberG ?? 0) } : nil
        let sug: Double? = foodItems.contains(where: { $0.sugarG != nil })
            ? foodItems.reduce(0.0) { $0 + ($1.sugarG ?? 0) } : nil
        let sod: Double? = foodItems.contains(where: { $0.sodiumMg != nil })
            ? foodItems.reduce(0.0) { $0 + ($1.sodiumMg ?? 0) } : nil

        totals = NutrientTotals(
            calories: cal, proteinG: pro, carbsG: carb, fatG: fat,
            fiberG: fib, sugarG: sug, sodiumMg: sod
        )

        // Rebuild core healthkit samples from totals
        var samples: [HealthKitSample] = [
            .init(identifier: "dietaryEnergyConsumed", value: cal, unit: "kcal"),
            .init(identifier: "dietaryProtein", value: pro, unit: "g"),
            .init(identifier: "dietaryCarbohydrates", value: carb, unit: "g"),
            .init(identifier: "dietaryFatTotal", value: fat, unit: "g"),
        ]
        if let fib { samples.append(.init(identifier: "dietaryFiber", value: fib, unit: "g")) }
        if let sug { samples.append(.init(identifier: "dietarySugar", value: sug, unit: "g")) }
        if let sod { samples.append(.init(identifier: "dietarySodium", value: sod, unit: "mg")) }

        healthkitSamples = samples
    }
}

// MARK: - Food Item

struct FoodItem: Codable, Identifiable {
    var itemId: UUID
    var id: UUID { itemId }
    var name: String
    var portion: String
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double?
    var sugarG: Double?
    var sodiumMg: Double?

    enum CodingKeys: String, CodingKey {
        case itemId
        case name, portion, calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case sugarG = "sugar_g"
        case sodiumMg = "sodium_mg"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        itemId = (try? c.decodeIfPresent(UUID.self, forKey: .itemId)) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        portion = try c.decode(String.self, forKey: .portion)
        calories = try c.decode(Double.self, forKey: .calories)
        proteinG = try c.decode(Double.self, forKey: .proteinG)
        carbsG = try c.decode(Double.self, forKey: .carbsG)
        fatG = try c.decode(Double.self, forKey: .fatG)
        fiberG = try? c.decodeIfPresent(Double.self, forKey: .fiberG)
        sugarG = try? c.decodeIfPresent(Double.self, forKey: .sugarG)
        sodiumMg = try? c.decodeIfPresent(Double.self, forKey: .sodiumMg)
    }

    init(
        itemId: UUID = UUID(),
        name: String, portion: String,
        calories: Double, proteinG: Double, carbsG: Double, fatG: Double,
        fiberG: Double? = nil, sugarG: Double? = nil, sodiumMg: Double? = nil
    ) {
        self.itemId = itemId
        self.name = name
        self.portion = portion
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.sugarG = sugarG
        self.sodiumMg = sodiumMg
    }
}

// MARK: - Nutrient Totals

struct NutrientTotals: Codable {
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double?
    var sugarG: Double?
    var sodiumMg: Double?

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
    var identifier: String
    var value: Double
    var unit: String
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
