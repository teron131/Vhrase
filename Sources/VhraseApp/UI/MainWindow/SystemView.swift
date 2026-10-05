// Owns readiness actions, credential focus and persistence boundaries, and optional installation confirmation.

import AppKit
import SwiftUI

struct SystemView: View {
  @ObservedObject var appState: AppState
  @Binding var selectedTab: MainWindowTab
  @State private var isOpenCCInstallConfirmationPresented = false
  @State private var credentialFocusMonitor = CredentialFocusMonitor()
  @FocusState private var focusedSecretField: SecretKey?
  private var presentation: DictationPresentation { appState.presentation }

  var body: some View {
    systemTab
      .mainWindowEvents(
        appState: appState, blocksEscape: isOpenCCInstallConfirmationPresented,
        onDeactivate: finishAPIKeyEditing
      )
      .confirmationDialog(
        "Install OpenCC?", isPresented: $isOpenCCInstallConfirmationPresented,
        titleVisibility: .visible
      ) {
        Button("Install with Homebrew") { appState.installOpenCC() }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          "Vhrase will run “brew install opencc”. Homebrew may download OpenCC and its required packages."
        )
      }
      .onChange(of: focusedSecretField) { _, field in
        if field != nil {
          credentialFocusMonitor.start(onOutsideClick: finishAPIKeyEditing)
        } else {
          credentialFocusMonitor.stop()
        }
      }
      .onDisappear(perform: finishAPIKeyEditing)
  }

  private var systemTab: some View {
    let diagnostics = appState.setupDiagnostics
    return mainWindowPage(spacing: 26) {
      pageHeader(
        "System",
        description: "Manage provider credentials, macOS access, and optional capabilities."
      )

      if let primary = diagnostics.first {
        setupOverviewCard(primary)
      }

      keysCard
      permissionsCard
      diagnosticsFullCard(diagnostics)
    }
  }

  private func setupOverviewCard(_ diagnostic: SetupDiagnostic) -> some View {
    HStack(alignment: .center, spacing: 14) {
      Image(systemName: diagnostic.systemImage)
        .font(.system(size: 22, weight: .bold))
        .foregroundStyle(.white)
        .frame(width: 50, height: 50)
        .background(VhraseTheme.diagnosticColor(diagnostic.severity), in: Circle())
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text(setupOverviewTitle(diagnostic))
          .font(VhraseFont.statusTitle)
        Text(setupOverviewDetail(diagnostic))
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 16)

      if let actionTitle = setupDiagnosticActionTitle(diagnostic) {
        Button(actionTitle) {
          handleSetupDiagnostic(diagnostic)
        }
        .buttonStyle(.borderedProminent)
        .disabled(
          diagnostic.id == .openCC
            && appState.openCCInstallationState == .installing
        )
      }
    }
    .padding(18)
    .surface()
  }

  private var keysCard: some View {
    settingsGroup(
      "Provider credentials",
      footer:
        "Secrets stay in your login Keychain and save automatically without password dialogs. An uppercase _KEY name is saved as an environment reference that survives rebuilds without Keychain access. LLM_BASE_URL overrides the saved endpoint when present. Unsaved secrets remain in memory for this session."
    ) {
      keyField(.xaiAPIKey)
      keyField(.elevenLabsAPIKey)
      keyField(.geminiAPIKey)
      keyField(.llmAPIKey)
      configurationField(
        "LLM base URL",
        text: Binding(
          get: { appState.effectiveLLMBaseURL },
          set: { value in
            guard !appState.usesEnvironmentLLMBaseURL else { return }
            appState.updateSettings { $0.adjustmentBaseURL = value }
          }
        ),
        environmentName: appState.usesEnvironmentLLMBaseURL ? "LLM_BASE_URL" : nil
      )

      settingsRow(
        "Model access",
        detail: "Sends only a tiny “Reply with OK” request using the configured model."
      ) {
        Button {
          appState.checkLLMModelAccess()
        } label: {
          HStack(spacing: 6) {
            if appState.isCheckingLLMModelAccess {
              ProgressView()
                .controlSize(.small)
            } else {
              Image(systemName: "checkmark.seal")
            }
            Text(appState.isCheckingLLMModelAccess ? "Checking model…" : "Check model access")
          }
        }
        .buttonStyle(.bordered)
        .disabled(appState.isCheckingLLMModelAccess || appState.effectiveAPIKey(.llmAPIKey).isEmpty)
      }

      if !appState.unsavedAPIKeys.isEmpty {
        HStack {
          Label("Unsaved credential changes", systemImage: "exclamationmark.circle")
            .foregroundStyle(VhraseTheme.statusWarning)
          Spacer()
          Button("Retry saving") { appState.retrySavingAPIKeys() }
            .controlSize(.small)
        }
        .font(.callout)
        .settingsRowStyle()
      }

      if !appState.keychainReadNotice.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Label("Saved credentials need Keychain access", systemImage: "lock")
            .font(.callout.weight(.medium))
          Text(appState.keychainReadNotice)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          Button("Retry reading saved keys") { appState.retryLoadingAPIKeys() }
            .controlSize(.small)
        }
        .settingsRowStyle()
      }
    }
  }

  private func keyField(_ key: SecretKey) -> some View {
    let text = Binding(
      get: { appState.apiKeyField(key) },
      set: { appState.updateAPIKey(key, value: $0) }
    )
    return settingsRow(key.title) {
      HStack(spacing: 12) {
        Group {
          if showsCredentialReference(text.wrappedValue) {
            TextField(key.title, text: text)
          } else {
            SecureField(key.title, text: text)
          }
        }
        .textFieldStyle(.roundedBorder)
        .labelsHidden()
        .frame(width: 320)
        .transaction { transaction in
          transaction.animation = nil
        }
        .focused($focusedSecretField, equals: key)
        .onSubmit {
          finishAPIKeyEditing()
        }

        keyStatus(key)
      }
    }
  }

  private func showsCredentialReference(_ value: String) -> Bool {
    !value.isEmpty
      && value.utf8.allSatisfy { byte in
        byte == 95 || (65...90).contains(byte)
      }
  }

  private func configurationField(
    _ title: String,
    text: Binding<String>,
    environmentName: String?
  ) -> some View {
    settingsRow(title, detail: environmentName.map { "Loaded from \($0)" }) {
      HStack(spacing: 12) {
        TextField(title, text: text)
          .textFieldStyle(.roundedBorder)
          .labelsHidden()
          .frame(width: 320)
          .disabled(environmentName != nil)
        if environmentName != nil {
          credentialState(
            "Environment", systemImage: "checkmark.circle.fill", color: VhraseTheme.statusSuccess)
        } else {
          Color.clear.frame(width: 96, height: 1)
        }
      }
    }
  }

  private var permissionsCard: some View {
    settingsGroup(
      "Permissions",
      footer:
        "Microphone is required. Shortcut, paste, and screen access appear only when the features you chose need them."
    ) {
      ForEach(relevantPermissionSnapshots) { snapshot in
        permissionTile(snapshot)
      }
    } accessory: {
      Button {
        appState.refreshPermissions()
      } label: {
        Label("Refresh", systemImage: "arrow.clockwise")
      }
      .buttonStyle(AccentLinkButtonStyle())
      .font(.callout)
    }
  }

  private func diagnosticsFullCard(_ diagnostics: [SetupDiagnostic]) -> some View {
    settingsGroup("Readiness details") {
      ForEach(diagnostics) { diagnostic in
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: diagnostic.systemImage)
            .foregroundStyle(VhraseTheme.diagnosticColor(diagnostic.severity))
            .frame(width: 20)
            .padding(.top, 1)
          VStack(alignment: .leading, spacing: 2) {
            Text(diagnostic.title)
            Text(diagnostic.detail)
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            if diagnostic.id == .openCC,
              let failureMessage = appState.openCCInstallationState.failureMessage
            {
              Text(failureMessage)
                .font(.caption)
                .foregroundStyle(VhraseTheme.statusWarning)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
          Spacer()
          if diagnostic.id == .openCC,
            appState.openCCInstallationState == .installing
          {
            ProgressView()
              .controlSize(.small)
              .accessibilityLabel("Installing OpenCC")
          }
          if let actionTitle = setupDiagnosticActionTitle(diagnostic) {
            Button(actionTitle) {
              handleSetupDiagnostic(diagnostic)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(
              diagnostic.id == .openCC
                && appState.openCCInstallationState == .installing
            )
          }
        }
        .settingsRowStyle()
        .accessibilityElement(children: .contain)
      }
    }
  }

  private func setupOverviewTitle(_ diagnostic: SetupDiagnostic) -> String {
    return switch diagnostic.id {
    case .ready, .openCC:
      "Ready to dictate"
    case .screenPermission, .accessibilityPermission:
      "Recording is ready"
    case .transcriptionConfiguration, .providerKey, .microphonePermission, .adjustmentKey:
      "Finish setup"
    }
  }

  /// Shows the least-privileged permission path for the currently selected shortcut and output behavior.
  private var relevantPermissionSnapshots: [PermissionSnapshot] {
    appState.permissions.filter { snapshot in
      switch snapshot.permission {
      case .microphone:
        true
      case .inputMonitoring:
        appState.settings.hotkeyPreset == .fn
      case .screenRecording:
        appState.settings.adjustWithLLM && appState.settings.includeScreenshot
      case .accessibility:
        true
      }
    }
  }

  private func setupOverviewDetail(_ diagnostic: SetupDiagnostic) -> String {
    if diagnostic.id == .openCC,
      let failureMessage = appState.openCCInstallationState.failureMessage
    {
      return failureMessage
    }
    return switch diagnostic.id {
    case .ready:
      "The selected provider and required permissions are ready."
    case .openCC, .screenPermission, .accessibilityPermission:
      "Core recording works. \(diagnostic.detail)"
    case .transcriptionConfiguration, .providerKey, .microphonePermission, .adjustmentKey:
      diagnostic.detail
    }
  }

  private func setupDiagnosticActionTitle(_ diagnostic: SetupDiagnostic) -> String? {
    switch diagnostic.id {
    case .transcriptionConfiguration:
      "Review Transcription"
    case .providerKey, .adjustmentKey:
      "Add Key"
    case .microphonePermission:
      "Request Access"
    case .screenPermission:
      "Open Settings"
    case .accessibilityPermission:
      if presentation.permissionSnapshot(.accessibility)?.requestedBefore == true {
        "Open Settings"
      } else if appState.settings.hotkeyPreset == .fn {
        "Enable Shortcut & Insertion"
      } else {
        "Enable Insertion"
      }
    case .openCC:
      if appState.openCCInstallationState == .installing {
        "Installing…"
      } else if !appState.canInstallOpenCC {
        "Get Homebrew"
      } else if appState.openCCInstallationState.failureMessage != nil {
        "Retry Install"
      } else {
        "Install OpenCC"
      }
    case .ready:
      nil
    }
  }

  /// Routes the leading setup issue to the existing configuration or macOS permission action.
  private func handleSetupDiagnostic(_ diagnostic: SetupDiagnostic) {
    switch diagnostic.id {
    case .transcriptionConfiguration:
      selectedTab = .capture
    case .providerKey:
      focusedSecretField = SecretKey(appState.settings.provider)
    case .adjustmentKey:
      focusedSecretField = .llmAPIKey
    case .microphonePermission:
      appState.handlePermissionAction(.microphone)
    case .screenPermission:
      appState.handlePermissionAction(.screenRecording)
    case .accessibilityPermission:
      appState.handlePermissionAction(.accessibility)
    case .openCC:
      if appState.canInstallOpenCC {
        isOpenCCInstallConfirmationPresented = true
      } else {
        appState.openHomebrewSetup()
      }
    case .ready:
      break
    }
  }

  /// Reports where the effective credential comes from beside the field that edits it.
  private func keyStatus(_ key: SecretKey) -> some View {
    let isReady = !appState.effectiveAPIKey(key).isEmpty
    return credentialState(
      appState.usesEnvironmentFallback(for: key)
        ? "Environment" : (isReady ? "Saved" : "Missing"),
      systemImage: isReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
      color: isReady ? VhraseTheme.statusSuccess : VhraseTheme.statusWarning
    )
  }

  private func credentialState(_ title: String, systemImage: String, color: Color) -> some View {
    Label(title, systemImage: systemImage)
      .font(.caption.weight(.medium))
      .foregroundStyle(color)
      .frame(width: 96, alignment: .leading)
  }

  private func permissionTile(_ snapshot: PermissionSnapshot) -> some View {
    HStack(spacing: 12) {
      Image(systemName: snapshot.permission.systemImage)
        .frame(width: 20)
        .foregroundStyle(
          snapshot.state.isReady ? VhraseTheme.statusSuccess : VhraseTheme.statusWarning
        )
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(snapshot.permission.title)
        Text(snapshot.state.title)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button(snapshot.actionTitle) {
        appState.handlePermissionAction(snapshot.permission)
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .accessibilityLabel("\(snapshot.actionTitle) for \(snapshot.permission.title)")
      .accessibilityHint(
        snapshot.state.isReady
          ? "Opens macOS permission settings"
          : "Requests access or opens macOS permission settings")
    }
    .settingsRowStyle()
  }

  /// Ends credential editing and commits any pending Keychain update.
  private func finishAPIKeyEditing() {
    focusedSecretField = nil
    credentialFocusMonitor.stop()
    appState.flushPendingAPIKeySave()
  }
}

/// Owns the AppKit event monitor used to dismiss credential focus.
@MainActor
final class CredentialFocusMonitor {
  private var eventMonitor: Any?

  /// Starts one local monitor and reports clicks that land outside every text input.
  func start(onOutsideClick: @escaping () -> Void) {
    guard eventMonitor == nil else {
      return
    }

    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
      guard let contentView = event.window?.contentView else {
        return event
      }

      let location = contentView.convert(event.locationInWindow, from: nil)
      guard !Self.containsTextInput(at: location, in: contentView) else {
        return event
      }

      DispatchQueue.main.async {
        onOutsideClick()
      }
      return event
    }
  }

  /// Removes the local monitor when credential editing ends.
  func stop() {
    guard let eventMonitor else {
      return
    }
    NSEvent.removeMonitor(eventMonitor)
    self.eventMonitor = nil
  }

  private static func containsTextInput(
    at location: NSPoint,
    in contentView: NSView
  ) -> Bool {
    func containsTextInput(in view: NSView) -> Bool {
      if view is NSTextField || view is NSTextView {
        let localLocation = view.convert(location, from: contentView)
        if view.bounds.contains(localLocation) {
          return true
        }
      }

      for subview in view.subviews where containsTextInput(in: subview) {
        return true
      }
      return false
    }

    return containsTextInput(in: contentView)
  }
}
