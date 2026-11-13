import Foundation
import Security

/// Minimal generic-password Keychain wrapper. Items are device-only and
/// readable after first unlock, so they never leave the phone via backups.
struct KeychainStore {
    let service: String

    init(service: String = (Bundle.main.bundleIdentifier ?? "com.ganhoo.tally") + ".security") {
        self.service = service
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    @discardableResult
    func set(_ data: Data, for key: String) -> Bool {
        var query = baseQuery(key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            query.merge(attributes) { _, new in new }
            return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    func data(for key: String) -> Data? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    @discardableResult
    func delete(_ key: String) -> Bool {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: Typed helpers

    func bool(for key: String) -> Bool? {
        guard let d = data(for: key), let s = String(data: d, encoding: .utf8) else { return nil }
        return s == "1"
    }

    @discardableResult
    func set(_ value: Bool, for key: String) -> Bool {
        set(Data((value ? "1" : "0").utf8), for: key)
    }

    func int(for key: String) -> Int? {
        guard let d = data(for: key), let s = String(data: d, encoding: .utf8) else { return nil }
        return Int(s)
    }

    @discardableResult
    func set(_ value: Int, for key: String) -> Bool {
        set(Data(String(value).utf8), for: key)
    }
}
