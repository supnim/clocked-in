import Foundation
import Security
import OSLog

class IdentityService {
    static let shared = IdentityService()

    private let log = Logger(subsystem: "com.clockedin", category: "IdentityService")
    private let keychainKey = "user_uuid"
    private let keychainService = "com.clockedin.app"

    private init() {}

    /// Gets the user's UUID, generating one if it doesn't exist
    func getOrCreateUserUUID() -> String {
        // Try to retrieve existing UUID from Keychain
        if let existingUUID = getUUIDFromKeychain() {
            return existingUUID
        }

        // Generate new UUID
        let newUUID = UUID().uuidString

        // Store in Keychain
        if saveUUIDToKeychain(newUUID) {
            return newUUID
        } else {
            // Fallback if Keychain fails (shouldn't happen in practice)
            log.warning("Failed to save UUID to Keychain, using in-memory UUID")
            return newUUID
        }
    }

    private func getUUIDFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let uuidString = String(data: data, encoding: .utf8) else {
            return nil
        }

        return uuidString
    }

    private func saveUUIDToKeychain(_ uuid: String) -> Bool {
        guard let data = uuid.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        // If item already exists, update it
        if status == errSecDuplicateItem {
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: keychainKey
            ]
            let updateAttributes: [String: Any] = [
                kSecValueData as String: data
            ]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
            return updateStatus == errSecSuccess
        }

        return status == errSecSuccess
    }
}