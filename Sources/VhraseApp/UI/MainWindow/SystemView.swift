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
    return ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        pageHeader(
          "System",
          description: "Manage provider credentials, macOS access, and optional capabilities.",
          systemImage: MainWindowTab.system.systemImage
        )

        if let primary = diagnostics.first {
          setupOverviewCard(primary)
            .hoverLift()
        }

        ViewThatFits(in: .horizontal) {
          HStack(alignment: .top, spacing: 20) {
            keysCard
              .frame(minWidth: 430, maxWidth: 460)
              .hoverLift()

            VStack(spacing: 16) {
              permissionsCard
                .frame(minWidth: 470)
                .hoverLift()
              diagnosticsFullCard(diagnostics)
                .hoverLift()
            }
            .frame(maxWidth: .infinity)
          }

          VStack(spacing: 16) {
            keysCard
              .hoverLift()
            permissionsCard
              .hoverLift()
            diagnosticsFullCard(diagnostics)
              .hoverLift()
          }
          .frame(maxWidth: .infinity)
        }
      }
      .frame(maxWidth: 1040, alignment: .topLeading)
      .padding(32)
      .frame(maxWidth: .infinity, alignment: .top)
    }
  }

  private func setupOverviewCard(_ diagnostic: SetupDiagnostic) -> some View {
    HStack(alignment: .center, spacing: 14) {
      Image(systemName: diagnostic.systemImage)
        .font(.system(size: 25, weight: .semibold))
        .foregroundStyle(VhraseTheme.diagnosticColor(diagnostic.severity))
        .frame(width: 48, height: 48)
        .background(
          VhraseTheme.diagnosticColor(diagnostic.severity).opacity(0.12),
          in: Circle()
        )
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 4) {
        Text(setupOverviewTitle(diagnostic))
          .font(.title3.weight(.semibold))
          .tracking(-0.2)
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
        .tint(VhraseTheme.accent)
        .disabled(
          diagnostic.id == .openCC
            && appState.openCCInstallationState == .installing
        )
      }
    }
    .operationalSurface()
  }

  private var keysCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      sectionHeader(
        "Provider credentials",
        description:
          "Secrets stay in your login Keychain. An uppercase _KEY name is saved as an environment reference. LLM_BASE_URL overrides the saved endpoint when present."
      )

      Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
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
      }
      .frame(maxWidth: .infinity)

      LazyVGrid(
        columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10
      ) {
        keyStatus("xAI", key: .xaiAPIKey)
        keyStatus("ElevenLabs", key: .elevenLabsAPIKey)
        keyStatus("LLM", key: .llmAPIKey)
        keyStatus("Gemini", key: .geminiAPIKey)
      }

      HStack(spacing: 10) {
        Button {
          appState.checkLLMModelAccess()
        } label: {
          HStack(spacing: 6) {
            if appState.isCheckingLLMModelAccess {
              ProgressView()
                .controlSize(.small)
            } else {
              Image(systemName: "bolt.horizontal.circle")
            }
            Text(appState.isCheckingLLMModelAccess ? "Testing LLM…" : "Test LLM")
          }
        }
        .buttonStyle(.bordered)
        .disabled(appState.isCheckingLLMModelAccess || appState.effectiveAPIKey(.llmAPIKey).isEmpty)

        Text("Sends only a tiny “Reply with OK” request using the configured model.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Text(
        "Credentials save automatically without password dialogs. Environment references survive rebuilds without Keychain access; unsaved secrets remain in memory for this session."
      )
      .font(.caption)
      .foregroundStyle(.secondary)

      if !appState.unsavedAPIKeys.isEmpty {
        HStack {
          Label("Unsaved credential changes", systemImage: "exclamationmark.circle")
            .foregroundStyle(VhraseTheme.statusWarning)
          Spacer()
          Button("Retry saving") { appState.retrySavingAPIKeys() }
        }
        .font(.caption)
      }

      if !appState.keychainReadNotice.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Label("Saved credentials need Keychain access", systemImage: "lock")
            .font(.callout.weight(.medium))
          Text(appState.keychainReadNotice)
            .font(.caption)
            .foregroundStyle(.secondary)
          Button("Retry reading saved keys") { appState.retryLoadingAPIKeys() }
        }
      }
    }
    .contentSection()
  }

  private func keyField(_ key: SecretKey) -> some View {
    let text = Binding(
      get: { appState.apiKeyField(key) },
      set: { appState.updateAPIKey(key, value: $0) }
    )
    return GridRow {
      Text(key.title)
        .font(.callout.weight(.medium))
        .gridColumnAlignment(.trailing)

      Group {
        if showsCredentialReference(text.wrappedValue) {
          TextField(key.title, text: text)
        } else {
          SecureField(key.title, text: text)
        }
      }
      .textFieldStyle(.roundedBorder)
      .frame(minWidth: 280, maxWidth: .infinity)
      .gridColumnAlignment(.leading)
      .transaction { transaction in
        transaction.animation = nil
      }
      .focused($focusedSecretField, equals: key)
      .onSubmit {
        finishAPIKeyEditing()
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
    GridRow {
      Text(title)
        .font(.callout.weight(.medium))
        .gridColumnAlignment(.trailing)

      VStack(alignment: .leading, spacing: 5) {
        TextField(title, text: text)
          .textFieldStyle(.roundedBorder)
          .disabled(environmentName != nil)
        if let environmentName {
          Label("Loaded from \(environmentName)", systemImage: "checkmark.circle.fill")
            .font(.caption)
            .foregroundStyle(VhraseTheme.statusSuccess)
        }
      }
      .frame(minWidth: 280, maxWidth: .infinity)
      .gridColumnAlignment(.leading)
    }
  }

  private var permissionsCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        sectionHeader(
          "Permissions",
          description: "Grant only the macOS access required by the features you use.")
        Spacer()
        Button {
          appState.refreshPermissions()
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
        if let microphone = presentation.permissionSnapshot(.microphone),
          !microphone.state.isReady
        {
          Button {
            appState.handlePermissionAction(.microphone)
          } label: {
            Label(
              microphone.state == .notDetermined
                ? "Request Microphone" : "Open Microphone Settings",
              systemImage: "mic.badge.plus"
            )
          }
        }
      }

      LazyVGrid(
        columns: [GridItem(.flexible()), GridItem(.flexible())],
        alignment: .leading,
        spacing: 10
      ) {
        ForEach(relevantPermissionSnapshots) { snapshot in
          permissionTile(snapshot)
        }
      }

      Text(
        "Microphone is required. Shortcut, paste, and screen access appear only when the features you chose need them."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .contentSection()
  }

  private func diagnosticsFullCard(_ diagnostics: [SetupDiagnostic]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionHeader(
        "Readiness details",
        description: "Review the selected provider, permissions, and optional capabilities.")

      ForEach(diagnostics) { diagnostic in
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: diagnostic.systemImage)
            .foregroundStyle(VhraseTheme.diagnosticColor(diagnostic.severity))
            .frame(width: 22)
          VStack(alignment: .leading, spacing: 2) {
            Text(diagnostic.title)
              .font(.headline)
            Text(diagnostic.detail)
              .font(.callout)
              .foregroundStyle(.secondary)
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
            .disabled(
              diagnostic.id == .openCC
                && appState.openCCInstallationState == .installing
            )
          }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
      }
    }
    .contentSection()
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

  private func keyStatus(_ title: String, key: SecretKey) -> some View {
    let isReady = !appState.effectiveAPIKey(key).isEmpty
    return StatusPill(
      title: appState.usesEnvironmentFallback(for: key)
        ? "\(title) from environment"
        : (isReady ? "\(title) ready" : "\(title) missing"),
      systemImage: isReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
      color: isReady ? VhraseTheme.statusSuccess : VhraseTheme.statusWarning
    )
  }

  private func permissionTile(_ snapshot: PermissionSnapshot) -> some View {
    Button {
      appState.handlePermissionAction(snapshot.permission)
    } label: {
      HStack(spacing: 10) {
        Image(systemName: snapshot.permission.systemImage)
          .font(.body)
          .frame(width: 22)
          .foregroundStyle(
            snapshot.state.isReady ? VhraseTheme.statusSuccess : VhraseTheme.statusWarning)
        VStack(alignment: .leading, spacing: 2) {
          Text(snapshot.permission.title)
            .font(.subheadline.weight(.medium))
          Text(snapshot.displayTitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.tertiary)
      }
      .padding(12)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity)
    .insetField(cornerRadius: 10)
    .accessibilityHint(
      snapshot.state.isReady
        ? "Opens macOS permission settings" : "Requests access or opens macOS permission settings")
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
