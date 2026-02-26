import SwiftUI
import PhotosUI

// MARK: - Nutrition View (root)

struct NutritionView: View {
    @EnvironmentObject private var nutritionManager: NutritionManager

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Navigation header
                HStack {
                    Text("Nutrition")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        Task { await nutritionManager.loadRecentMeals() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                // Daily summary + chat in a scrollable layout
                VStack(spacing: 12) {
                    DailySummaryCard(summary: nutritionManager.todaySummary)
                        .padding(.horizontal, 16)

                    NutritionChatSection()
                }
            }
        }
        .task {
            await nutritionManager.refreshSummary()
        }
    }
}

// MARK: - Daily Summary Card

struct DailySummaryCard: View {
    let summary: DailyNutritionSummary?

    private var calories: Double { summary?.totalCalories ?? 0 }
    private var protein: Double { summary?.totalProteinG ?? 0 }
    private var carbs: Double   { summary?.totalCarbsG ?? 0 }
    private var fat: Double     { summary?.totalFatG ?? 0 }
    private var meals: Int      { summary?.mealCount ?? 0 }

    private var macroTotal: Double { protein + carbs + fat }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                    Text("\(Int(calories)) kcal")
                        .font(.title.bold())
                        .foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(meals)")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text(meals == 1 ? "meal" : "meals")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            // Macro pills
            HStack(spacing: 10) {
                MacroPill(label: "Protein", value: protein, unit: "g", color: .blue)
                MacroPill(label: "Carbs",   value: carbs,   unit: "g", color: .orange)
                MacroPill(label: "Fat",     value: fat,     unit: "g", color: .yellow)
            }

            // Macro bar
            if macroTotal > 0 {
                MacroBar(protein: protein, carbs: carbs, fat: fat, total: macroTotal)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 8)
            }
        }
        .cardStyle()
    }
}

// MARK: - Macro Pill

struct MacroPill: View {
    let label: String
    let value: Double
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(Int(value))\(unit)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.3), lineWidth: 0.5)
        )
    }
}

// MARK: - Macro Bar

struct MacroBar: View {
    let protein: Double
    let carbs: Double
    let fat: Double
    let total: Double

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue.opacity(0.8))
                    .frame(width: geo.size.width * protein / total)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.orange.opacity(0.8))
                    .frame(width: geo.size.width * carbs / total)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.yellow.opacity(0.8))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 8)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Chat Section

struct NutritionChatSection: View {
    @EnvironmentObject private var nutritionManager: NutritionManager

    @State private var inputText: String = ""
    @State private var selectedImage: PhotosPickerItem? = nil
    @State private var selectedImageData: Data? = nil
    @State private var showingPhotoPicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if nutritionManager.messages.isEmpty {
                            EmptyStateView()
                                .padding(.top, 40)
                        } else {
                            ForEach(nutritionManager.messages) { message in
                                ChatBubble(message: message)
                                    .id(message.id)
                            }
                        }

                        if nutritionManager.isAnalyzing {
                            TypingIndicator()
                                .id("typing")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
                .onChange(of: nutritionManager.messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.3)) {
                        if let last = nutritionManager.messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: nutritionManager.isAnalyzing) { _, analyzing in
                    if analyzing {
                        withAnimation { proxy.scrollTo("typing", anchor: .bottom) }
                    }
                }
            }

            // Image preview
            if let imageData = selectedImageData,
               let uiImage = UIImage(data: imageData) {
                HStack {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.cardBorder, lineWidth: 0.5)
                        )

                    Button {
                        selectedImageData = nil
                        selectedImage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.7))
                            .font(.title3)
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.cardBackground)
            }

            // Input bar
            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedImage,
                             matching: .images,
                             photoLibrary: .shared()) {
                    Image(systemName: selectedImageData != nil
                          ? "photo.fill"
                          : "camera.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(selectedImageData != nil ? .green : .white.opacity(0.7))
                        .frame(width: 36, height: 36)
                }
                .onChange(of: selectedImage) { _, item in
                    Task {
                        guard let item else { return }
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            selectedImageData = data
                        }
                    }
                }

                TextField("Describe a meal or ask about nutrition…", text: $inputText, axis: .vertical)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .lineLimit(1...4)

                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(canSend ? .green : .white.opacity(0.25))
                }
                .disabled(!canSend)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.cardBackground)
            .overlay(
                Rectangle()
                    .fill(Color.cardBorder)
                    .frame(height: 0.5),
                alignment: .top
            )
        }
    }

    private var canSend: Bool {
        (!inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
         || selectedImageData != nil)
        && !nutritionManager.isAnalyzing
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageData = selectedImageData

        inputText = ""
        selectedImageData = nil
        selectedImage = nil

        Task {
            await nutritionManager.sendMessage(
                text: text.isEmpty ? "Analyze this food photo." : text,
                imageData: imageData
            )
        }
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: NutritionChatMessage

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                // Photo thumbnail for user messages
                if isUser, let data = message.imageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 160, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                        )
                }

                // Text bubble
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(isUser ? Color(red: 0.13, green: 0.37, blue: 0.58) : Color.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(isUser ? Color.clear : Color.cardBorder, lineWidth: 0.5)
                        )
                }

                // Nutrition result card for assistant messages
                if let result = message.analysisResult {
                    NutritionResultCard(result: result)
                }

                // Timestamp
                Text(timeString(from: message.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.35))
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }

    private func timeString(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}

// MARK: - Nutrition Result Card

struct NutritionResultCard: View {
    let result: NutritionAnalysisResult
    @State private var showingMicronutrients = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Macro summary row
            HStack(spacing: 0) {
                MacroStat(value: result.totals.calories, label: "kcal", color: .white)
                Divider().frame(height: 30).background(Color.cardBorder)
                MacroStat(value: result.totals.proteinG, label: "protein", color: .blue)
                Divider().frame(height: 30).background(Color.cardBorder)
                MacroStat(value: result.totals.carbsG, label: "carbs", color: .orange)
                Divider().frame(height: 30).background(Color.cardBorder)
                MacroStat(value: result.totals.fatG, label: "fat", color: .yellow)
            }

            Divider().background(Color.cardBorder)

            // Food items
            VStack(alignment: .leading, spacing: 6) {
                ForEach(result.foodItems) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white)
                            Text(item.portion)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                        Text("\(Int(item.calories)) kcal")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }

            // Micronutrients toggle
            let hasMicros = result.totals.fiberG != nil
                || result.totals.sugarG != nil
                || result.totals.sodiumMg != nil

            if hasMicros {
                Button {
                    withAnimation(.spring(duration: 0.25)) {
                        showingMicronutrients.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(showingMicronutrients ? "Hide details" : "Show more details")
                            .font(.caption)
                        Image(systemName: showingMicronutrients
                              ? "chevron.up"
                              : "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(.white.opacity(0.5))
                }

                if showingMicronutrients {
                    VStack(alignment: .leading, spacing: 4) {
                        if let fiber = result.totals.fiberG {
                            MicroRow(label: "Fiber", value: fiber, unit: "g")
                        }
                        if let sugar = result.totals.sugarG {
                            MicroRow(label: "Sugar", value: sugar, unit: "g")
                        }
                        if let sodium = result.totals.sodiumMg {
                            MicroRow(label: "Sodium", value: sodium, unit: "mg")
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(14)
        .background(Color(red: 0.08, green: 0.10, blue: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.cardBorder, lineWidth: 0.5)
        )
        .frame(maxWidth: 300)
    }
}

// MARK: - Macro Stat (inside result card)

struct MacroStat: View {
    let value: Double
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(Int(value))")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Micro Row

struct MicroRow: View {
    let label: String
    let value: Double
    let unit: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(String(format: "%.1f %@", value, unit))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var phase: Int = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: 7, height: 7)
                        .scaleEffect(phase == i ? 1.3 : 0.8)
                        .animation(
                            .easeInOut(duration: 0.4)
                                .repeatForever()
                                .delay(Double(i) * 0.15),
                            value: phase
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.cardBorder, lineWidth: 0.5)
            )
            Spacer(minLength: 60)
        }
        .onAppear { phase = 1 }
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "fork.knife.circle")
                .font(.system(size: 52))
                .foregroundStyle(.white.opacity(0.2))

            Text("Log a Meal")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.6))

            Text("Describe what you ate or snap a photo.\nNutrition data will be saved to Apple Health.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}
