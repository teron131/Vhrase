// Shows where a credential comes from, the same way on System, which edits it, and on the pages whose features depend on it.

import SwiftUI

/// Names a credential's source: saved in Keychain, read from the environment, or missing.
struct CredentialStatusLabel: View {
  let key: SecretKey
  @ObservedObject var credentials: Credentials

  var body: some View {
    let isReady = !credentials.effectiveValue(key).isEmpty
    Label(
      credentials.usesEnvironmentFallback(for: key)
        ? "Environment" : (isReady ? "Saved" : "Missing"),
      systemImage: isReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
    )
    .font(.caption.weight(.medium))
    .foregroundStyle(isReady ? VhraseTheme.statusSuccess : VhraseTheme.statusWarning)
  }
}

/// A credential's state on a page that needs it, with a jump to its field on System, which stays its only editor.
struct CredentialSummaryRow: View {
  let key: SecretKey
  @ObservedObject var credentials: Credentials
  /// Completes "Add it in System to …", such as "transcribe with xAI".
  let purpose: String
  let open: () -> Void

  var body: some View {
    let isMissing = credentials.effectiveValue(key).isEmpty
    settingsRow(key.title, detail: detail(isMissing: isMissing)) {
      HStack(spacing: 12) {
        CredentialStatusLabel(key: key, credentials: credentials)
        if isMissing {
          Button("Add Key", action: open)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
          Button("Change", action: open)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
      }
    }
  }

  private func detail(isMissing: Bool) -> String {
    if isMissing {
      return "Add it in System to \(purpose)."
    }
    guard credentials.usesEnvironmentFallback(for: key) else {
      return "Saved in your login Keychain."
    }
    let reference = credentials.field(key)
    return "Read from \(reference.isEmpty ? key.rawValue : reference) in your environment."
  }
}
