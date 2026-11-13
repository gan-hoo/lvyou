import Foundation
import LocalAuthentication
import Observation

/// How long the app may stay in the background before it locks again.
enum LockGracePeriod: Int, CaseIterable, Identifiable {
    case immediately = 0
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .immediately: String(localized: "Immediately")
        case .oneMinute: String(localized: "After 1 minute")
        case .fiveMinutes: String(localized: "After 5 minutes")
        case .fifteenMinutes: String(localized: "After 15 minutes")
        }
    }
}

enum BiometryKind {
    case faceID, touchID, opticID, none

    var title: String {
        switch self {
        case .faceID: String(localized: "Face ID")
        case .touchID: String(localized: "Touch ID")
        case .opticID: String(localized: "Optic ID")
        case .none: String(localized: "Passcode")
        }
    }

    var symbol: String {
        switch self {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        case .none: "lock"
        }
    }
}

/// Face ID / Touch ID app lock. Settings are kept in the Keychain so they
/// cannot be switched off by editing the app's preferences file.
@Observable
@MainActor
final class AppLockManager {
    private enum Key {
        static let enabled = "appLock.enabled"
        static let grace = "appLock.grace"
        static let privacyCover = "appLock.privacyCover"
    }

    private let keychain: KeychainStore

    private(set) var isEnabled: Bool
    private(set) var isLocked: Bool
    private(set) var isAuthenticating = false
    var lastError: String?

    private(set) var gracePeriod: LockGracePeriod

    /// Blur the app in the app switcher even when the lock is off.
    private(set) var privacyCover: Bool

    func setGracePeriod(_ value: LockGracePeriod) {
        gracePeriod = value
        keychain.set(value.rawValue, for: Key.grace)
    }

    func setPrivacyCover(_ value: Bool) {
        privacyCover = value
        keychain.set(value, for: Key.privacyCover)
    }

    private var backgroundedAt: Date?

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
        let enabled = keychain.bool(for: Key.enabled) ?? false
        self.isEnabled = enabled
        self.isLocked = enabled
        self.gracePeriod = LockGracePeriod(rawValue: keychain.int(for: Key.grace) ?? 0) ?? .immediately
        self.privacyCover = keychain.bool(for: Key.privacyCover) ?? true
    }

    var biometry: BiometryKind {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return .none }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .none
        }
    }

    /// Whether any owner authentication (biometrics or passcode) is available.
    var canAuthenticate: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// Biometrics first, falling back to the device passcode.
    func authenticate(reason: String = String(localized: "Unlock your ledger")) async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        context.localizedCancelTitle = String(localized: "Cancel")
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            lastError = nil
            return ok
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel:
                lastError = nil
            default:
                lastError = error.localizedDescription
            }
            return false
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func unlock() async {
        guard isLocked else { return }
        if await authenticate() {
            withMotion(DS.Motion.gentle) { isLocked = false }
            Haptics.success()
        }
    }

    /// Turning the lock on requires a successful authentication first.
    func setEnabled(_ enabled: Bool) async {
        if enabled {
            guard canAuthenticate else {
                lastError = String(localized: "Set up a device passcode or Face ID in iOS Settings first.")
                return
            }
            guard await authenticate(reason: String(localized: "Confirm to turn on App Lock")) else { return }
        } else {
            guard await authenticate(reason: String(localized: "Confirm to turn off App Lock")) else { return }
        }
        keychain.set(enabled, for: Key.enabled)
        isEnabled = enabled
        isLocked = false
    }

    // MARK: Scene phase

    func didEnterBackground() {
        backgroundedAt = .now
        if isEnabled && gracePeriod == .immediately {
            isLocked = true
        }
    }

    func willEnterForeground() {
        guard isEnabled, let since = backgroundedAt else { return }
        if Date.now.timeIntervalSince(since) >= TimeInterval(gracePeriod.rawValue) {
            isLocked = true
        }
        backgroundedAt = nil
    }
}
