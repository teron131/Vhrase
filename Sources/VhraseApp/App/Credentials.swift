// Owns Vhrase's credentials for one app session: where each value comes from, the fields the System page edits, their debounced Keychain saves, and the value a request finally uses.

import Combine
import Foundation

/// Keeps editable credential values apart from their environment fallbacks, so a field never shows or saves a secret the user did not enter there.
@MainActor
final class Credentials: ObservableObject {
  private static let developmentEnvironmentFileArgument = "--development-environment-file"

  /// Editable values: saved secrets, this session's edits, or the LLM environment reference, never environment fallbacks.
  @Published private var fields: [SecretKey: String] = [:]
  @Published private(set) var unsavedKeys: Set<SecretKey> = []
  @Published private(set) var keychainReadNotice = ""
  /// What went wrong reading `~/.zshrc` or the development environment file at launch, or empty.
  let environmentNotice: String
  /// Receives save outcomes and Keychain read failures for the app's transient notice.
  var onNotice: (String) -> Void = { _ in }

  private let store: APIKeyStore
  private var saveTask: Task<Void, Never>?
  private var pendingSaves: Set<SecretKey> = []
  private var editedKeys: Set<SecretKey> = []
  private var shouldLoadSavedKeys: Bool

  /// Resolves environment fallbacks from the launch environment, `~/.zshrc`, and the development file in that order; a development launch never reads Keychain.
  init() {
    let developmentEnvironmentFileURL = Self.developmentEnvironmentFileURL(
      arguments: CommandLine.arguments
    )
    var notices: [String] = []
    var environment = ProcessInfo.processInfo.environment
    do {
      environment = try APIKeyStore.zshrcEnvironment(baseEnvironment: environment)
    } catch {
      notices.append(
        "Could not read API keys from ~/.zshrc: \(error.localizedDescription)"
      )
    }
    if let developmentEnvironmentFileURL {
      do {
        environment = try APIKeyStore.developmentEnvironment(
          fileURL: developmentEnvironmentFileURL,
          baseEnvironment: environment
        )
      } catch {
        notices.append(
          "Could not read development credentials: \(error.localizedDescription)"
        )
      }
    }
    let store = APIKeyStore(environment: environment)
    self.store = store
    environmentNotice = notices.joined(separator: " ")
    shouldLoadSavedKeys = developmentEnvironmentFileURL == nil
    fields = [.llmAPIKey: store.savedLLMCredentialReference()]
  }

  /// Returns the credential field shown for editing, which excludes environment fallbacks.
  func field(_ key: SecretKey) -> String {
    fields[key, default: ""]
  }

  /// Resolves the credential a request will use: the edited or saved field first, then its environment fallback.
  func effectiveValue(_ key: SecretKey) -> String {
    store.effectiveValue(for: key, savedValue: field(key))
  }

  func usesEnvironmentFallback(for key: SecretKey) -> Bool {
    store.usesEnvironmentFallback(for: key, savedValue: field(key))
  }

  /// Resolves the non-secret LLM endpoint from the environment before the saved setting.
  func effectiveLLMBaseURL(savedValue: String) -> String {
    store.effectiveLLMBaseURL(savedValue: savedValue)
  }

  var usesEnvironmentLLMBaseURL: Bool {
    store.usesEnvironmentLLMBaseURL
  }

  /// Loads Keychain credentials after the menu-bar lifecycle is established without blocking AppKit launch.
  func loadSavedAfterLaunch() {
    guard shouldLoadSavedKeys else {
      return
    }
    shouldLoadSavedKeys = false

    let store = store
    let keys = SecretKey.allCases.filter { key in
      !editedKeys.contains(key)
        && !(key == .llmAPIKey
          && APIKeyStore.isCredentialEnvironmentVariableName(field(.llmAPIKey)))
    }
    Task {
      let loaded = await Task.detached {
        var values: [SecretKey: String] = [:]
        var notices: [String] = []

        for key in keys {
          do {
            values[key] = try store.savedValue(for: key)
          } catch {
            notices.append(error.localizedDescription)
          }
        }
        return (values: values, notices: notices)
      }.value

      for key in keys where !editedKeys.contains(key) {
        guard let value = loaded.values[key] else { continue }
        fields[key] = value
      }

      let keychainNotice = loaded.notices.joined(separator: " ")
      keychainReadNotice = keychainNotice
      if !keychainNotice.isEmpty {
        // A launch that could read neither source reports both problems together.
        onNotice(
          [environmentNotice, keychainNotice]
            .filter { !$0.isEmpty }
            .joined(separator: " "))
      }
    }
  }

  /// Retries inaccessible saved keys without a password dialog or overwriting credentials edited during this session.
  func retryLoading() {
    shouldLoadSavedKeys = true
    loadSavedAfterLaunch()
  }

  /// Updates one editable credential and debounces its Keychain write for 500 milliseconds.
  func update(_ key: SecretKey, value: String) {
    guard value != field(key) else {
      return
    }

    fields[key] = value

    pendingSaves.insert(key)
    editedKeys.insert(key)
    unsavedKeys.insert(key)
    saveTask?.cancel()
    saveTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(nanoseconds: 500_000_000)
      } catch {
        return
      }
      guard !Task.isCancelled else {
        return
      }
      self?.savePending()
    }
  }

  /// Flushes credentials edited on a disappearing configuration surface, or before the app exits.
  func flushPendingSave() {
    guard saveTask != nil || !pendingSaves.isEmpty else {
      return
    }
    saveTask?.cancel()
    savePending()
  }

  /// Retries explicit credential edits without opening a system authentication dialog.
  func retrySaving() {
    save(unsavedKeys)
  }

  /// Completes the pending Keychain batch and clears its debounce state.
  private func savePending() {
    saveTask = nil
    let keys = pendingSaves
    pendingSaves.removeAll()
    save(keys)
  }

  /// Saves only explicitly edited credentials so an unrelated field cannot erase an unread Keychain item.
  private func save(_ keys: Set<SecretKey>) {
    guard !keys.isEmpty else {
      return
    }
    var failures: [String] = []
    for key in keys {
      let value = field(key)
      if key == .llmAPIKey,
        APIKeyStore.isCredentialEnvironmentVariableName(value)
      {
        store.saveLLMCredentialReference(value)
        unsavedKeys.remove(key)
        continue
      }
      if key == .llmAPIKey {
        store.saveLLMCredentialReference("")
      }
      do {
        try store.save(value, for: key)
        unsavedKeys.remove(key)
      } catch {
        unsavedKeys.insert(key)
        failures.append(error.localizedDescription)
      }
    }
    onNotice(
      failures.isEmpty
        ? "Credential changes saved. Secrets use macOS Keychain; environment references use local preferences."
        : failures.joined(separator: " ") + " Unsaved changes apply only for this session.")
  }

  /// Reads the development environment path paired with the launch-only argument.
  private static func developmentEnvironmentFileURL(arguments: [String]) -> URL? {
    guard let argumentIndex = arguments.firstIndex(of: developmentEnvironmentFileArgument) else {
      return nil
    }
    let pathIndex = arguments.index(after: argumentIndex)
    guard arguments.indices.contains(pathIndex) else {
      return nil
    }
    return URL(fileURLWithPath: arguments[pathIndex])
  }
}
