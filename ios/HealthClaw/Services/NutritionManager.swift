import Foundation
import SwiftUI

@MainActor
final class NutritionManager: ObservableObject {

    // MARK: - Published State

    @Published var messages: [NutritionChatMessage] = []
    @Published var isAnalyzing: Bool = false
    @Published var todaySummary: DailyNutritionSummary?
    @Published var recentMeals: [NutritionAnalysisResult] = []
    @Published var errorMessage: String?

    // MARK: - Private State

    private var service: NutritionService?
    private var healthManager: HealthKitManager?

    // MARK: - Configuration

    /// Call this once (e.g. from HealthClawApp) to inject dependencies.
    func configure(settings: AppSettings, healthManager: HealthKitManager) {
        self.service = NutritionService(settings: settings)
        self.healthManager = healthManager
    }

    // MARK: - Send Message

    func sendMessage(text: String, imageData: Data?) async {
        guard let service else {
            errorMessage = "NutritionManager not configured."
            return
        }

        // 1. Append the user message immediately
        let userMessage = NutritionChatMessage(
            role: .user,
            text: text,
            imageData: imageData
        )
        withAnimation { messages.append(userMessage) }

        isAnalyzing = true
        errorMessage = nil

        do {
            // 2. Call the server
            let result = try await service.analyzeFood(text: text, imageData: imageData)

            // 3. Build assistant reply text
            let replyText = result.description.isEmpty
                ? "Here's the nutritional breakdown for your meal:"
                : result.description

            let assistantMessage = NutritionChatMessage(
                role: .assistant,
                text: replyText,
                analysisResult: result
            )
            withAnimation { messages.append(assistantMessage) }

            // 4. Add to recent meals (most-recent first)
            recentMeals.insert(result, at: 0)

            // 5. Auto-write to HealthKit
            await writeToHealthKit(result: result)

            // 6. Refresh daily summary
            await refreshSummary()

        } catch {
            let errorMsg = NutritionChatMessage(
                role: .assistant,
                text: "Sorry, I couldn't analyze that. \(error.localizedDescription)"
            )
            withAnimation { messages.append(errorMsg) }
            errorMessage = error.localizedDescription
        }

        isAnalyzing = false
    }

    // MARK: - Refresh Summary

    func refreshSummary() async {
        guard let service else { return }
        do {
            todaySummary = try await service.fetchDailySummary(date: Date())
        } catch {
            // Non-fatal: summary may not be available
            print("[NutritionManager] Summary fetch failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Load Recent Meals

    func loadRecentMeals(days: Int = 7) async {
        guard let service else { return }
        do {
            recentMeals = try await service.fetchHistory(days: days)
        } catch {
            print("[NutritionManager] History fetch failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Write to HealthKit

    func writeToHealthKit(result: NutritionAnalysisResult) async {
        guard let service else { return }
        do {
            try await service.writeHealthKitSamples(from: result)
        } catch {
            print("[NutritionManager] HealthKit write failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Clear Conversation

    func clearConversation() {
        messages.removeAll()
    }
}
