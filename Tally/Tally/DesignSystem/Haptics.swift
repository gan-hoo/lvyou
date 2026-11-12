import UIKit

/// Thin wrapper around UIKit feedback generators that honours the user's haptics setting.
@MainActor
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    private static var enabled: Bool { AppSettings.hapticsEnabled }

    /// Keypad taps and small toggles.
    static func tap() {
        guard enabled else { return }
        light.impactOccurred(intensity: 0.7)
    }

    static func softTap() {
        guard enabled else { return }
        soft.impactOccurred()
    }

    static func press() {
        guard enabled else { return }
        rigid.impactOccurred(intensity: 0.6)
    }

    static func selection() {
        guard enabled else { return }
        selectionGenerator.selectionChanged()
    }

    static func success() {
        guard enabled else { return }
        notification.notificationOccurred(.success)
    }

    static func warning() {
        guard enabled else { return }
        notification.notificationOccurred(.warning)
    }

    static func error() {
        guard enabled else { return }
        notification.notificationOccurred(.error)
    }
}
