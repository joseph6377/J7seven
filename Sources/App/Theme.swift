import SwiftUI
import UIKit

// MARK: - Color Hex Initializer

extension Color {
    /// Initialize a Color from a hex string (supports RGB, RGB+alpha forms).
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Adaptive Semantic Color Tokens

extension Color {
    /// Builds a dynamic Color that resolves differently in light vs dark mode.
    private static func adaptive(light: String, dark: String) -> Color {
        Color(UIColor { trait in
            UIColor(Color(hex: trait.userInterfaceStyle == .dark ? dark : light))
        })
    }

    /// App screen background. Light: cool off-white (#F7F8FC). Dark: deep obsidian to match the player.
    static let j7AppBackground = adaptive(light: "F7F8FC", dark: "0C0C0E")

    /// Elevated surfaces — cards, sheets, list containers. Light: pure white. Dark: slightly lifted obsidian.
    static let j7Surface = adaptive(light: "FFFFFF", dark: "18181B")

    /// Hairline borders and dividers. Light: soft cool gray (#E6E8EC). Dark: subtle light separator.
    static let j7Border = adaptive(light: "E6E8EC", dark: "2C2C30")
}
