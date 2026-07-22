// Stores Vhrase API credentials in the macOS Keychain and synchronizes explicit launch-environment overrides.

import Foundation
import Security

enum SecretKey: String, CaseIterable {
    case xaiAPIKey = "XAI_API_KEY"
    case elevenLabsAPIKey = "ELEVENLABS_API_KEY"
    case llmAPIKey = "AI_GATEWAY_API_KEY"

    var title: String {
        switch self {
        case .xaiAPIKey:
            "xAI API key"
        case .elevenLabsAPIKey:
            "ElevenLabs API key"
        case .llmAPIKey:
            "LLM API key"
        }
    }
}

/// Persists secrets as generic-password items and never reads the retired plaintext preference keys.
final class APIKeyStore {
    private let service: String
    private let environment: [String: String]

    init(
        service: String = "Vhrase",
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.service = service
        self.environment = environment
    }

    func environmentValue(for key: SecretKey) -> String {
        environment[key.rawValue] ?? ""
    }

    /// Persists only nonempty supported launch overrides so later GUI launches retain their credentials.
    func importEnvironmentValues() throws -> Set<SecretKey> {
        var imported: Set<SecretKey> = []
        for key in SecretKey.allCases {
            let value = environmentValue(for: key)
            guard !value.isEmpty else {
                continue
            }
            try save(value, for: key)
            imported.insert(key)
        }
        return imported
    }

    /// Ignores editable-field writes while a launch override owns the effective credential.
    func saveEditableValue(_ value: String, for key: SecretKey) throws {
        guard environmentValue(for: key).isEmpty else {
            return
        }
        try save(value, for: key)
    }

    /// Skips Keychain access when an environment override already supplies the effective credential.
    func savedValueForEditing(for key: SecretKey) throws -> String {
        guard environmentValue(for: key).isEmpty else {
            return ""
        }
        return try savedValue(for: key)
    }

    /// Reads only the editable Keychain value so environment credentials never enter persisted UI state.
    func savedValue(for key: SecretKey) throws -> String {
        var result: CFTypeRef?
        var query = keychainQuery(for: key)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                throw KeychainReadError(
                    key: key,
                    message: "Keychain returned invalid credential data."
                )
            }
            return value
        case errSecItemNotFound:
            return ""
        default:
            throw KeychainReadError(
                key: key,
                message: keychainMessage(for: status)
            )
        }
    }

    /// Resolves a launch environment override before an explicitly supplied saved value.
    func effectiveValue(
        for key: SecretKey,
        savedValue: String
    ) -> String {
        let environmentValue = environmentValue(for: key)
        return environmentValue.isEmpty ? savedValue : environmentValue
    }

    /// Saves or removes one credential and reports Keychain failures without including the secret value.
    func save(_ value: String, for key: SecretKey) throws {
        if value.isEmpty {
            try removeValue(for: key)
            return
        }

        let data = Data(value.utf8)
        let update: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(
            keychainQuery(for: key) as CFDictionary,
            update as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainSaveError(key: key, action: "update", status: updateStatus)
        }

        var item = keychainQuery(for: key)
        item[kSecValueData] = data
        item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainSaveError(key: key, action: "save", status: addStatus)
        }
    }

    private func keychainQuery(for key: SecretKey) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key.rawValue,
        ]
    }

    private func removeValue(for key: SecretKey) throws {
        let status = SecItemDelete(keychainQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSaveError(key: key, action: "remove", status: status)
        }
    }
}

private struct KeychainReadError: LocalizedError {
    let key: SecretKey
    let message: String

    var errorDescription: String? {
        "Could not read \(key.title) from macOS Keychain: \(message)"
    }
}

private struct KeychainSaveError: LocalizedError {
    let key: SecretKey
    let action: String
    let status: OSStatus

    var errorDescription: String? {
        "Could not \(action) \(key.title) in macOS Keychain: \(keychainMessage(for: status))."
    }
}

private func keychainMessage(for status: OSStatus) -> String {
    (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
}
