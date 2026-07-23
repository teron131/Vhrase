// Stores editable Vhrase API credentials in Keychain and uses launch-environment values only to fill missing keys.

import Foundation
import Security

enum SecretKey: String, CaseIterable {
    case xaiAPIKey = "XAI_API_KEY"
    case elevenLabsAPIKey = "ELEVENLABS_API_KEY"
    case llmAPIKey = "LLM_API_KEY"

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

    /// Resolves supported development credentials without executing or expanding the environment file.
    static func developmentEnvironment(
        fileURL: URL,
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> [String: String] {
        var environment = baseEnvironment
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return environment
        }

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let supportedKeys = Set(SecretKey.allCases.map(\.rawValue))
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"),
                  let separator = line.firstIndex(of: "=") else {
                continue
            }

            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            guard supportedKeys.contains(key), environment[key, default: ""].isEmpty else {
                continue
            }

            let valueStart = line.index(after: separator)
            let rawValue = String(line[valueStart...]).trimmingCharacters(in: .whitespaces)
            environment[key] = unquotedEnvironmentValue(rawValue)
        }
        return environment
    }

    func environmentValue(for key: SecretKey) -> String {
        environment[key.rawValue] ?? ""
    }

    /// Persists user input even when the launch environment supplies a fallback credential.
    func saveEditableValue(_ value: String, for key: SecretKey) throws {
        try save(value, for: key)
    }

    /// Reads the editable Keychain value without substituting environment fallback text into the field.
    func savedValueForEditing(for key: SecretKey) throws -> String {
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

    /// Resolves an explicitly saved credential before its launch-environment fallback.
    func effectiveValue(
        for key: SecretKey,
        savedValue: String
    ) -> String {
        savedValue.isEmpty ? environmentValue(for: key) : savedValue
    }

    func usesEnvironmentFallback(
        for key: SecretKey,
        savedValue: String
    ) -> Bool {
        savedValue.isEmpty && !environmentValue(for: key).isEmpty
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

private func unquotedEnvironmentValue(_ value: String) -> String {
    guard value.count >= 2, let first = value.first, let last = value.last,
          (first == "\"" && last == "\"") || (first == "'" && last == "'") else {
        return value
    }
    return String(value.dropFirst().dropLast())
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
