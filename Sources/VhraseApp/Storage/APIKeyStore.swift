// Stores editable Vhrase API credentials in Keychain and resolves safe environment-backed provider configuration.

import Foundation
import Security

enum SecretKey: String, CaseIterable {
  case xaiAPIKey = "XAI_API_KEY"
  case elevenLabsAPIKey = "ELEVENLABS_API_KEY"
  case geminiAPIKey = "GEMINI_API_KEY"
  case llmAPIKey = "LLM_API_KEY"

  var title: String {
    switch self {
    case .xaiAPIKey:
      "xAI API key"
    case .elevenLabsAPIKey:
      "ElevenLabs API key"
    case .geminiAPIKey:
      "Gemini API key"
    case .llmAPIKey:
      "LLM API key"
    }
  }

  /// Names the credential each transcription provider authenticates with.
  init(_ provider: STTProvider) {
    self =
      switch provider {
      case .xai: .xaiAPIKey
      case .elevenLabs: .elevenLabsAPIKey
      case .gemini: .geminiAPIKey
      }
  }
}

/// Persists secrets as generic-password items and resolves provider configuration without exposing environment values in editable state.
final class APIKeyStore: Sendable {
  private static let supportedConfigurationKeys = Set(["LLM_BASE_URL"])
  private static let llmCredentialReferenceKey = "credentialReference.LLM_API_KEY"
  private let service: String
  private let environment: [String: String]
  private let defaultsSuiteName: String?

  init(
    service: String = "Vhrase",
    environment: [String: String] = ProcessInfo.processInfo.environment,
    defaultsSuiteName: String? = nil
  ) {
    self.service = service
    self.environment = environment
    self.defaultsSuiteName = defaultsSuiteName
  }

  /// Resolves supported development credentials without executing or expanding the environment file.
  static func developmentEnvironment(
    fileURL: URL,
    baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
  ) throws -> [String: String] {
    try fileEnvironment(
      fileURL: fileURL,
      baseEnvironment: baseEnvironment,
      requiresExportPrefix: false,
      valueParser: unquotedEnvironmentValue
    )
  }

  /// Reads direct literal API-key exports from zsh configuration without executing shell code.
  static func zshrcEnvironment(
    fileURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zshrc"),
    baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
  ) throws -> [String: String] {
    try fileEnvironment(
      fileURL: fileURL,
      baseEnvironment: baseEnvironment,
      requiresExportPrefix: true,
      valueParser: literalZshEnvironmentValue
    )
  }

  private static func fileEnvironment(
    fileURL: URL,
    baseEnvironment: [String: String],
    requiresExportPrefix: Bool,
    valueParser: (String) -> String?
  ) throws -> [String: String] {
    var environment = baseEnvironment
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return environment
    }

    let contents = try String(contentsOf: fileURL, encoding: .utf8)
    let supportedKeys = Set(SecretKey.allCases.map(\.rawValue))
    for rawLine in contents.split(whereSeparator: \.isNewline) {
      var assignment = rawLine.trimmingCharacters(in: .whitespaces)
      guard !assignment.isEmpty, !assignment.hasPrefix("#") else {
        continue
      }
      let hasExportPrefix = assignment.hasPrefix("export ") || assignment.hasPrefix("export\t")
      if hasExportPrefix {
        assignment = String(assignment.dropFirst("export".count))
          .trimmingCharacters(in: .whitespaces)
      } else if requiresExportPrefix {
        continue
      }
      guard let separator = assignment.firstIndex(of: "=")
      else {
        continue
      }

      let key = String(assignment[..<separator]).trimmingCharacters(in: .whitespaces)
      guard
        supportedKeys.contains(key) || supportedConfigurationKeys.contains(key)
          || isCredentialEnvironmentVariableName(key),
        environment[key, default: ""].isEmpty
      else {
        continue
      }

      let valueStart = assignment.index(after: separator)
      let rawValue = String(assignment[valueStart...]).trimmingCharacters(in: .whitespaces)
      guard let value = valueParser(rawValue) else {
        continue
      }
      environment[key] = value
    }
    return environment
  }

  func environmentValue(for key: SecretKey) -> String {
    environment[key.rawValue] ?? ""
  }

  /// Resolves the non-secret LLM endpoint from the environment before the saved UI setting.
  func effectiveLLMBaseURL(savedValue: String) -> String {
    llmBaseURLFromEnvironment.isEmpty ? savedValue : llmBaseURLFromEnvironment
  }

  var usesEnvironmentLLMBaseURL: Bool {
    !llmBaseURLFromEnvironment.isEmpty
  }

  private var llmBaseURLFromEnvironment: String {
    environment["LLM_BASE_URL", default: ""]
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Reads only the editable Keychain value without prompting, keeping launch nonblocking and environment fallbacks out of persisted UI state.
  func savedValue(for key: SecretKey) throws -> String {
    var result: CFTypeRef?
    var query = keychainQuery(for: key)
    query[kSecReturnData] = true
    query[kSecMatchLimit] = kSecMatchLimitOne
    let status = KeychainInteraction.performWithoutUI {
      SecItemCopyMatching(query as CFDictionary, &result)
    }
    switch status {
    case errSecSuccess:
      guard let data = result as? Data,
        let value = String(data: data, encoding: .utf8)
      else {
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

  /// Resolves an explicitly saved credential before its launch-environment fallback, treating a conventional variable name in the LLM field as an indirect secret reference.
  func effectiveValue(
    for key: SecretKey,
    savedValue: String
  ) -> String {
    guard !savedValue.isEmpty else {
      return environmentValue(for: key)
    }
    guard key == .llmAPIKey, Self.isCredentialEnvironmentVariableName(savedValue) else {
      return savedValue
    }
    return environment[savedValue] ?? ""
  }

  func usesEnvironmentFallback(
    for key: SecretKey,
    savedValue: String
  ) -> Bool {
    if savedValue.isEmpty {
      return !environmentValue(for: key).isEmpty
    }
    return key == .llmAPIKey
      && Self.isCredentialEnvironmentVariableName(savedValue)
      && !environment[savedValue, default: ""].isEmpty
  }

  /// Loads the nonsecret environment-variable name chosen for the LLM credential.
  func savedLLMCredentialReference() -> String {
    let value = defaults.string(forKey: Self.llmCredentialReferenceKey) ?? ""
    return Self.isCredentialEnvironmentVariableName(value) ? value : ""
  }

  /// Persists an LLM environment-variable name outside Keychain because the reference is configuration, not a secret.
  func saveLLMCredentialReference(_ value: String) {
    if Self.isCredentialEnvironmentVariableName(value) {
      defaults.set(value, forKey: Self.llmCredentialReferenceKey)
    } else {
      defaults.removeObject(forKey: Self.llmCredentialReferenceKey)
    }
  }

  static func isCredentialEnvironmentVariableName(_ value: String) -> Bool {
    guard value.hasSuffix("_KEY"), let first = value.utf8.first,
      first == 95 || (65...90).contains(first)
    else {
      return false
    }
    return value.utf8.allSatisfy { byte in
      byte == 95 || (48...57).contains(byte) || (65...90).contains(byte)
    }
  }

  private var defaults: UserDefaults {
    guard let defaultsSuiteName,
      let defaults = UserDefaults(suiteName: defaultsSuiteName)
    else {
      return .standard
    }
    return defaults
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
    let updateStatus = KeychainInteraction.performWithoutUI {
      SecItemUpdate(keychainQuery(for: key) as CFDictionary, update as CFDictionary)
    }

    if updateStatus == errSecSuccess {
      return
    }
    guard updateStatus == errSecItemNotFound else {
      throw KeychainSaveError(key: key, action: "update", status: updateStatus)
    }

    var item = keychainQuery(for: key)
    item[kSecValueData] = data
    item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    let addStatus = KeychainInteraction.performWithoutUI {
      SecItemAdd(item as CFDictionary, nil)
    }
    guard addStatus == errSecSuccess else {
      throw KeychainSaveError(key: key, action: "save", status: addStatus)
    }
  }

  private func keychainQuery(for key: SecretKey) -> [CFString: Any] {
    return [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: key.rawValue,
    ]
  }

  private func removeValue(for key: SecretKey) throws {
    let status = KeychainInteraction.performWithoutUI {
      SecItemDelete(keychainQuery(for: key) as CFDictionary)
    }
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainSaveError(key: key, action: "remove", status: status)
    }
  }
}

/// Suppresses file-based Keychain dialogs only inside this process, without unlocking items or changing their access controls.
enum KeychainInteraction {
  private static let lock = NSLock()

  /// Serializes and restores the process-wide interaction flag because LAContext alone does not cover login Keychain items.
  static func performWithoutUI(_ operation: () -> OSStatus) -> OSStatus {
    lock.lock()
    defer { lock.unlock() }

    var wasAllowed = DarwinBoolean(false)
    let readStatus = SecKeychainGetUserInteractionAllowed(&wasAllowed)
    guard readStatus == errSecSuccess else { return readStatus }
    let disableStatus = SecKeychainSetUserInteractionAllowed(false)
    guard disableStatus == errSecSuccess else { return disableStatus }

    let operationStatus = operation()
    let restoreStatus = SecKeychainSetUserInteractionAllowed(wasAllowed.boolValue)
    return operationStatus == errSecSuccess ? restoreStatus : operationStatus
  }
}

private func unquotedEnvironmentValue(_ value: String) -> String {
  guard value.count >= 2, let first = value.first, let last = value.last,
    (first == "\"" && last == "\"") || (first == "'" && last == "'")
  else {
    return value
  }
  return String(value.dropFirst().dropLast())
}

private func literalZshEnvironmentValue(_ value: String) -> String? {
  guard !value.isEmpty else {
    return ""
  }

  if value.first == "'", value.last == "'" {
    let literal = String(value.dropFirst().dropLast())
    return literal.contains("'") ? nil : literal
  }

  if value.first == "\"", value.last == "\"" {
    let literal = String(value.dropFirst().dropLast())
    guard !literal.contains(where: { "$`\\".contains($0) }) else {
      return nil
    }
    return literal
  }

  let shellSyntax = CharacterSet.whitespacesAndNewlines.union(
    CharacterSet(charactersIn: "$`\\'\";|&<>(){}[]*?!~#")
  )
  guard value.rangeOfCharacter(from: shellSyntax) == nil else {
    return nil
  }
  return value
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
  if status == errSecInteractionNotAllowed || status == errSecAuthFailed {
    return
      "Access needs approval or the login Keychain is locked. Vhrase will not open a password dialog"
  }
  return (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
}
