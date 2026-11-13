import SwiftUI
import UIKit

/// Tally design system: colour, type, spacing, radius and motion tokens.
enum DS {
    // MARK: Colour

    enum Colors {
        /// User-selectable accent (Settings › Appearance). The root view is rebuilt when it changes.
        static var accent: Color { Color(hex: AppSettings.accentHex) }
        static let accentChoices = ["3E7BFA", "2AABEE", "5856D6", "3BB5A6", "16A06A", "E8932A", "EB5E8C", "8E8E93"]
        static let income = Color(light: "16A06A", dark: "3DD68C")
        static let expense = Color.primary
        static let transfer = Color(light: "5E7BAF", dark: "8FA7D6")
        static let warning = Color(light: "E8932A", dark: "F5A94A")
        static let danger = Color(light: "E5534B", dark: "FF6B63")

        static let background = Color(uiColor: .systemGroupedBackground)
        static let card = Color(uiColor: .secondarySystemGroupedBackground)
        static let elevated = Color(uiColor: .tertiarySystemGroupedBackground)
        static let fill = Color(uiColor: .tertiarySystemFill)
        static let separator = Color(uiColor: .separator)
        static let secondaryText = Color.secondary
        static let tertiaryText = Color(uiColor: .tertiaryLabel)

        /// Hairline used on glass surfaces to catch the light.
        static let glassStroke = Color(light: "FFFFFF", dark: "FFFFFF", lightOpacity: 0.55, darkOpacity: 0.10)

        static func amount(for kind: TransactionKind) -> Color {
            switch kind {
            case .expense: expense
            case .income: income
            case .transfer: transfer
            case .refund: income
            case .adjustment: Color.secondary
            }
        }

        static func budget(_ level: BudgetAlertLevel) -> Color {
            switch level {
            case .normal: accent
            case .approaching: warning
            case .exceeded: danger
            }
        }
    }

    /// Curated swatches for categories, accounts and tags: muted, legible in both modes.
    enum Palette {
        static let swatches: [String] = [
            "3E7BFA", "4A90E2", "47B5D9", "3BB5A6", "4CB782", "7C9A6D",
            "E8B730", "F2994A", "D98E5F", "B08968", "EB5757", "EB5E8C",
            "F07FA0", "9B6DD6", "6C7BF2", "7D8BA6", "5B6573", "8E8E93",
        ]
    }

    // MARK: Typography (SF Pro, Dynamic Type aware)

    enum Typography {
        static let heroAmount = Font.system(.largeTitle, design: .rounded, weight: .semibold)
        static let entryAmount = Font.system(size: 46, weight: .semibold, design: .rounded)
        static let cardAmount = Font.system(.title2, design: .rounded, weight: .semibold)
        static let rowAmount = Font.system(.body, design: .rounded, weight: .semibold)
        static let metric = Font.system(.headline, design: .rounded, weight: .semibold)
        static let sectionTitle = Font.system(.title3, design: .default, weight: .semibold)
        static let caption = Font.footnote
        static let micro = Font.caption2.weight(.medium)
        static let keypad = Font.system(.title3, design: .rounded, weight: .medium)
    }

    // MARK: Layout

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 28
        static let screen: CGFloat = 16
    }

    enum Radius {
        static let card: CGFloat = 22
        static let inner: CGFloat = 14
        static let control: CGFloat = 12
        static let icon: CGFloat = 10
        static let key: CGFloat = 16
    }

    // MARK: Motion

    enum Motion {
        static let spring = Animation.spring(response: 0.42, dampingFraction: 0.86)
        static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.8)
        static let gentle = Animation.spring(response: 0.6, dampingFraction: 0.9)
        static let reduced = Animation.easeInOut(duration: 0.18)

        /// Returns a crossfade-like animation when Reduce Motion is on.
        static func adaptive(_ animation: Animation) -> Animation {
            UIAccessibility.isReduceMotionEnabled ? reduced : animation
        }
    }
}

/// `withAnimation` that honours Reduce Motion.
@discardableResult
func withMotion<Result>(_ animation: Animation = DS.Motion.spring, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(DS.Motion.adaptive(animation), body)
}

// MARK: - Colour helpers

extension Color {
    init(hex: String, opacity: Double = 1) {
        self.init(uiColor: UIColor(hex: hex, alpha: opacity))
    }

    /// A dynamic colour that resolves differently in light and dark mode.
    init(light: String, dark: String, lightOpacity: Double = 1, darkOpacity: Double = 1) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkOpacity)
                : UIColor(hex: light, alpha: lightOpacity)
        })
    }
}

extension UIColor {
    convenience init(hex: String, alpha: Double = 1) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b: CGFloat
        if cleaned.count == 6 {
            r = CGFloat((value >> 16) & 0xFF) / 255
            g = CGFloat((value >> 8) & 0xFF) / 255
            b = CGFloat(value & 0xFF) / 255
        } else {
            r = 0.56; g = 0.56; b = 0.58
        }
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}
