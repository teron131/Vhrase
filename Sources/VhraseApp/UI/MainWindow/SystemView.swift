// Owns setup readiness, the only editors for API keys with their focus and persistence boundaries, macOS access, and settings import and export.

import AppKit
import SwiftUI

struct SystemView: View {
  @ObservedObject var appState: AppState
  let navigation: MainWindowNavigation
  /// A key another page asked to edit; System focuses and reveals its field, then clears the request.
  @Binding var credentialRequest: SecretKey?
  @State private var isOpenCCInstallConfirmationPresented = false
  @State private var credentialFocusMonitor = CredentialFocusMonitor()
  @FocusState private var focusedSecretField: SecretKey?
  private var presentation: DictationPresentation { appState.presentation }
  private var credentials: Credentials { appState.credentials }

  var body: some View {
    systemTab
      .mainWindowEvents(
        appState: appState, blocksEscape: isOpenCCInstallConfirmationPresented,
        onDeactivate: finishAPIKeyEditing
      )
      .openCCInstallConfirmation(
        isPresented: $isOpenCCInstallConfirmationPresented, setup: appState.openCCSetup
      )
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
    return ScrollViewReader { proxy in
      mainWindowPage(spacing: 26) {
        pageHeader(
          "System",
          description: "API keys, macOS access, and settings import and export."
        )

        if let primary = diagnostics.first {
          setupOverviewCard(primary, remaining: diagnostics.count - 1)
        }

        transcriptionKeysCard
        llmKeyCard
        credentialNotices
        permissionsCard
        customizationCard
      }
      .onAppear { revealRequestedCredential(proxy) }
      .onChange(of: credentialRequest) { _, _ in revealRequestedCredential(proxy) }
    }
  }

  private func revealRequestedCredential(_ proxy: ScrollViewProxy) {
    guard let key = credentialRequest else { return }
    credentialRequest = nil
    DispatchQueue.main.async {
      withAnimation(VhraseMotion.settle) {
        proxy.scrollTo(key, anchor: .center)
      }
      focusedSecretField = key
    }
  }

  private func setupOverviewCard(_ diagnostic: SetupDiagnostic, remaining: Int) -> some View {
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
        if remaining > 0, diagnostic.severity != .ready {
          Text(
            remaining == 1
              ? "1 more step after this one." : "\(remaining) more steps after this one."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }

      Spacer(minLength: 16)

      if let actionTitle = setupDiagnosticActionTitle(diagnostic) {
        Button(actionTitle) {
          handleSetupDiagnostic(diagnostic)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isDiagnosticActionRunning(diagnostic))
      }
    }
    .padding(18)
    .surface()
  }

  private var transcriptionKeysCard: some View {
    settingsGroup(
      "Transcription keys",
      footer:
        "Each key only unlocks that provider's transcription, never the LLM below. Keys save automatically to your login Keychain."
    ) {
      ForEach(ProviderLocation.cloud.providers.compactMap { SecretKey($0) }, id: \.self) { key in
        keyField(key)
      }
    }
  }

  private var llmKeyCard: some View {
    settingsGroup(
      "LLM key",
      footer:
        "Refinement uses this key with its endpoint and model. To use one account for both, enter its key here too. Type a variable name ending in _KEY, such as AI_GATEWAY_API_KEY, to read the key from your environment instead."
    ) {
      keyField(.llmAPIKey)
    }
  }

  /// Saving and reading problems can concern a key in either group, so they follow both instead of sitting inside one.
  @ViewBuilder private var credentialNotices: some View {
    if !credentials.unsavedKeys.isEmpty || !credentials.keychainReadNotice.isEmpty {
      settingsGroup {
        if !credentials.unsavedKeys.isEmpty {
          HStack {
            Label("Unsaved credential changes", systemImage: "exclamationmark.circle")
              .foregroundStyle(VhraseTheme.statusWarning)
            Spacer()
            Button("Retry saving") { credentials.retrySaving() }
              .controlSize(.small)
          }
          .font(.callout)
          .settingsRowStyle()
        }

        if !credentials.keychainReadNotice.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Label("Saved credentials need Keychain access", systemImage: "lock")
              .font(.callout.weight(.medium))
            Text(credentials.keychainReadNotice)
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            Button("Retry reading saved keys") { credentials.retryLoading() }
              .controlSize(.small)
          }
          .settingsRowStyle()
        }
      }
    }
  }

  private func keyField(_ key: SecretKey) -> some View {
    let text = Binding(
      get: { credentials.field(key) },
      set: { credentials.update(key, value: $0) }
    )
    return settingsRow(
      key.title,
      icon: { keyIcon(key) },
      control: {
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

          CredentialStatusLabel(key: key, credentials: credentials)
            .frame(width: 96, alignment: .leading)
        }
      }
    )
    .id(key)
  }

  @ViewBuilder private func keyIcon(_ key: SecretKey) -> some View {
    if let provider = STTProvider.allCases.first(where: { SecretKey($0) == key }),
      let icon = ProviderPicker.icon(for: provider)
    {
      Image(nsImage: icon)
    } else {
      llmIcon
    }
  }

  private var llmIcon: some View {
    Image(systemName: "brain")
      .foregroundStyle(.secondary)
  }

  private func showsCredentialReference(_ value: String) -> Bool {
    !value.isEmpty
      && value.utf8.allSatisfy { byte in
        byte == 95 || (65...90).contains(byte)
      }
  }

  private var permissionsCard: some View {
    settingsGroup(
      "Permissions",
      footer:
        "Input Monitoring appears only for Fn/Globe, and Screen Recording only when screen context is on."
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

  private var customizationCard: some View {
    settingsGroup("Your settings") {
      settingsRow(
        "Move to another Mac",
        detail:
          "Save every setting except API keys to a file, or load one. An import shows any sensitive change for review first."
      ) {
        HStack(spacing: 8) {
          Button {
            appState.importCustomization()
          } label: {
            Label("Import…", systemImage: "square.and.arrow.down")
          }
          Button {
            appState.exportCustomization()
          } label: {
            Label("Export…", systemImage: "square.and.arrow.up")
          }
        }
        .buttonStyle(.bordered)
      }
    }
  }

  private func setupOverviewTitle(_ diagnostic: SetupDiagnostic) -> String {
    return switch diagnostic.id {
    case .ready, .openCC:
      "Ready to dictate"
    case .screenPermission, .accessibilityPermission:
      "Recording is ready"
    case .transcriptionConfiguration, .providerKey, .localModel, .microphonePermission,
      .adjustmentKey:
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
    if let failureMessage = diagnosticFailureMessage(diagnostic) {
      return failureMessage
    }
    return switch diagnostic.id {
    case .ready:
      "The selected provider and required permissions are ready."
    case .openCC, .screenPermission, .accessibilityPermission:
      "Core recording works. \(diagnostic.detail)"
    case .transcriptionConfiguration, .providerKey, .localModel, .microphonePermission,
      .adjustmentKey:
      diagnostic.detail
    }
  }

  private func diagnosticFailureMessage(_ diagnostic: SetupDiagnostic) -> String? {
    switch diagnostic.id {
    case .openCC:
      appState.openCCSetup.failureMessage
    case .localModel:
      if case .failed(let message) = appState.selectedLocalModelStore?.state {
        message
      } else {
        nil
      }
    default:
      nil
    }
  }

  private func isDiagnosticActionRunning(_ diagnostic: SetupDiagnostic) -> Bool {
    switch diagnostic.id {
    case .openCC: appState.openCCSetup.installation == .installing
    case .localModel: appState.selectedLocalModelStore?.isDownloading == true
    default: false
    }
  }

  private func setupDiagnosticActionTitle(_ diagnostic: SetupDiagnostic) -> String? {
    switch diagnostic.id {
    case .transcriptionConfiguration:
      "Review Transcription"
    case .providerKey, .adjustmentKey:
      "Add Key"
    case .localModel:
      switch appState.selectedLocalModelStore?.state {
      case .downloading(let fraction, let isIndeterminate):
        OnDeviceModelStore.State.progressTitle(fraction: fraction, isIndeterminate: isIndeterminate)
      case .failed:
        "Retry Download"
      case .missing, .installed, nil:
        appState.selectedLocalModelStore?.downloadTitle
      }
    case .microphonePermission:
      "Request Access"
    case .screenPermission:
      "Open Settings"
    case .accessibilityPermission:
      presentation.insertionPermissionActionTitle
    case .openCC:
      appState.openCCSetup.installation == .installing
        ? "Installing…" : appState.openCCSetup.nextStepTitle
    case .ready:
      nil
    }
  }

  private func handleSetupDiagnostic(_ diagnostic: SetupDiagnostic) {
    switch diagnostic.id {
    case .transcriptionConfiguration:
      navigation.open(.transcription)
    case .providerKey:
      credentialRequest = SecretKey(appState.settings.provider)
    case .localModel:
      appState.selectedLocalModelStore?.download()
    case .adjustmentKey:
      credentialRequest = .llmAPIKey
    case .microphonePermission:
      appState.handlePermissionAction(.microphone)
    case .screenPermission:
      appState.handlePermissionAction(.screenRecording)
    case .accessibilityPermission:
      appState.handlePermissionAction(.accessibility)
    case .openCC:
      appState.openCCSetup.takeNextStep { isOpenCCInstallConfirmationPresented = true }
    case .ready:
      break
    }
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

  private func finishAPIKeyEditing() {
    focusedSecretField = nil
    credentialFocusMonitor.stop()
    credentials.flushPendingSave()
  }
}

@MainActor
final class CredentialFocusMonitor {
  private var eventMonitor: Any?

  /// Reports clicks that land outside every text input.
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
