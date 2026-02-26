import SwiftUI

// MARK: - App Colors

extension Color {
    static let appBackground = Color(red: 0.06, green: 0.07, blue: 0.10)
    static let cardBackground = Color(red: 0.11, green: 0.13, blue: 0.17)
    static let cardBorder = Color(white: 0.18)
}

// MARK: - Card Modifier

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.cardBorder, lineWidth: 0.5)
            )
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
}
