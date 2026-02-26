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

        let userMessage = NutritionChatMessage(
            role: .user,
            text: text,
            imageData: imageData
        )
        withAnimation { messages.append(userMessage) }

        isAnalyzing = true
        errorMessage = nil

        do {
            var result = try await service.analyzeFood(text: text, imageData: imageData)

            let uuids = try await service.writeHealthKitSamples(from: result)
            result.savedHKSampleUUIDs = uuids

            let replyText = result.description.isEmpty
                ? "Here's the nutritional breakdown for your meal:"
                : result.description

            let assistantMessage = NutritionChatMessage(
                role: .assistant,
                text: replyText,
                analysisResult: result
            )
            withAnimation { messages.append(assistantMessage) }

            recentMeals.insert(result, at: 0)
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

    // MARK: - Update Meal (from chat)

    func updateMeal(messageId: UUID, updatedResult: NutritionAnalysisResult) async {
        guard let service else { return }

        guard let idx = messages.firstIndex(where: { $0.id == messageId }),
              let oldResult = messages[idx].analysisResult else { return }

        var result = updatedResult
        result.recalculate()

        do {
            try await deleteHKSamples(for: oldResult)

            let newUUIDs = try await service.writeHealthKitSamples(from: result)
            result.savedHKSampleUUIDs = newUUIDs

            withAnimation { messages[idx].analysisResult = result }

            if let mealIdx = recentMeals.firstIndex(where: { $0.mealId == result.mealId }) {
                recentMeals[mealIdx] = result
            }

            await refreshSummary()
        } catch {
            print("[NutritionManager] Update failed: \(error.localizedDescription)")
            errorMessage = "Failed to update meal: \(error.localizedDescription)"
        }
    }

    // MARK: - Update Meal (from history, no chat message)

    func updateMealFromHistory(updatedResult: NutritionAnalysisResult, originalResult: NutritionAnalysisResult) async {
        guard let service else { return }

        var result = updatedResult
        result.recalculate()

        do {
            try await deleteHKSamples(for: originalResult)

            let newUUIDs = try await service.writeHealthKitSamples(from: result)
            result.savedHKSampleUUIDs = newUUIDs

            // Update in recentMeals
            if let mealIdx = recentMeals.firstIndex(where: { $0.mealId == result.mealId }) {
                recentMeals[mealIdx] = result
            }

            // Also update in chat if it exists there
            if let msgIdx = messages.firstIndex(where: { $0.analysisResult?.mealId == result.mealId }) {
                withAnimation { messages[msgIdx].analysisResult = result }
            }

            await refreshSummary()
        } catch {
            print("[NutritionManager] History update failed: \(error.localizedDescription)")
            errorMessage = "Failed to update meal: \(error.localizedDescription)"
        }
    }

    // MARK: - Delete Meal (from chat)

    func deleteMeal(messageId: UUID) async {
        guard service != nil else { return }

        guard let idx = messages.firstIndex(where: { $0.id == messageId }),
              let result = messages[idx].analysisResult else { return }

        try? await deleteHKSamples(for: result)

        withAnimation {
            messages.remove(at: idx)
            if idx > 0 && messages[idx - 1].role == .user {
                messages.remove(at: idx - 1)
            }
        }

        recentMeals.removeAll { $0.mealId == result.mealId }
        await refreshSummary()
    }

    // MARK: - Delete Meal (from history)

    func deleteMealFromHistory(result: NutritionAnalysisResult) async {
        try? await deleteHKSamples(for: result)

        recentMeals.removeAll { $0.mealId == result.mealId }

        // Also remove from chat if present
        if let msgIdx = messages.firstIndex(where: { $0.analysisResult?.mealId == result.mealId }) {
            withAnimation {
                messages.remove(at: msgIdx)
                if msgIdx > 0 && messages[msgIdx - 1].role == .user {
                    messages.remove(at: msgIdx - 1)
                }
            }
        }

        await refreshSummary()
    }

    // MARK: - Refresh Summary

    func refreshSummary() async {
        guard let service else { return }
        do {
            todaySummary = try await service.fetchDailySummary(date: Date())
        } catch {
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

    // MARK: - Clear Conversation

    func clearConversation() {
        messages.removeAll()
    }

    // MARK: - Private

    /// Delete HK samples for a result — uses tracked UUIDs if available, falls back to timestamp.
    private func deleteHKSamples(for result: NutritionAnalysisResult) async throws {
        guard let service else { return }
        if !result.savedHKSampleUUIDs.isEmpty {
            try await service.deleteHealthKitSamples(uuids: result.savedHKSampleUUIDs)
        } else {
            try await service.deleteHealthKitSamples(at: result.timestamp)
        }
    }
}
