import SwiftUI

/// Upside's look: Apple system styles plus a money-green accent.
enum Theme {
    /// Brand green, tuned for light and dark mode.
    static let accent = Color(light: 0x15803D, dark: 0x4ADE80)
    static let warning = Color(light: 0xD97706, dark: 0xFBBF24)
    static let over = Color(light: 0xDC2626, dark: 0xFF6961)

    /// The summary card's gradient (same in both modes, white text on top).
    static let heroGradient = LinearGradient(
        colors: [Color(hex: 0x15803D), Color(hex: 0x0E5A2B), Color(hex: 0x052E16)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let iconGradient = LinearGradient(
        colors: [Color(hex: 0x6EE7A0), Color(hex: 0x0F7A3C)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let cardGradients: [LinearGradient] = [
        (0x1D4ED8, 0x1E3A8A), (0xB91C1C, 0x7F1D1D), (0x7E22CE, 0x3B0764),
        (0x15803D, 0x052E16), (0xA16207, 0x422006), (0x0F766E, 0x042F2E),
        (0xBE185D, 0x500724), (0x334155, 0x0F172A),
    ].map {
        LinearGradient(colors: [Color(hex: $0.0), Color(hex: $0.1)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func cardGradient(for key: String) -> LinearGradient {
        var hash: UInt64 = 5381
        for byte in key.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return cardGradients[Int(hash % UInt64(cardGradients.count))]
    }
}

extension Owner {
    var color: Color {
        switch self {
        case .p1: return Color(hex: 0x0A84FF)
        case .p2: return Color(hex: 0xFF9F0A)
        case .shared: return Color(hex: 0x8E8E93)
        case .unassigned: return Color(hex: 0xC7C7CC)
        }
    }

    var ink: Color {
        switch self {
        case .p2, .unassigned: return Color(hex: 0x1A1100)
        default: return .white
        }
    }
}

// MARK: - Money

enum Money {
    private static let whole: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        f.minimumFractionDigits = 0
        return f
    }()

    private static let exactFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f
    }()

    /// "$1,240" — for cards and summaries.
    static func short(_ cents: Cents) -> String {
        whole.string(from: NSNumber(value: Double(abs(cents)) / 100)) ?? "$0"
    }

    /// "-$12.34" — for transactions and balances.
    static func exact(_ cents: Cents) -> String {
        exactFormatter.string(from: NSNumber(value: Double(cents) / 100)) ?? "$0.00"
    }
}

// MARK: - Colors from hex

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}
