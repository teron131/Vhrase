// Centralizes display policy and reusable controls for Vhrase's main-window destinations.

import AppKit
import Foundation
import SwiftUI

extension MainWindowView {
  var presentation: DictationPresentation {
    appState.presentation
  }

  /// Typographic card header; icons stay out of section titles to keep hierarchy editorial.
  func sectionHeader(
    _ title: String,
    description: String? = nil
  ) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(VhraseFont.headline)
      if let description {
        Text(description)
          .font(VhraseFont.caption)
          .foregroundStyle(VhraseTheme.inkSecondary)
      }
    }
  }

  /// Establishes a consistent page-level hierarchy before the destination's working controls.
  func pageHeader(
    _ title: String,
    description: String,
    systemImage: String
  ) -> some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: systemImage)
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(VhraseTheme.accent)
        .frame(width: 40, height: 40)
        .background(
          VhraseTheme.accentSubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(VhraseFont.pageTitle)
          .tracking(-0.5)
        Text(description)
          .font(VhraseFont.caption)
          .foregroundStyle(VhraseTheme.inkSecondary)
      }
    }
  }

  /// Keeps workflow navigation and its sole editor in one open, divider-led composition.
  func workflowEditor<Editor: View>(
    _ title: String,
    description: String,
    nodes: [PipelineFlowNode],
    selection: Binding<PipelineStage>,
    @ViewBuilder editor: () -> Editor
  ) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(title)
          .font(.subheadline.weight(.semibold))
        Text(description)
          .font(.caption)
          .foregroundStyle(VhraseTheme.inkSecondary)
      }

      HStack(alignment: .top, spacing: 0) {
        PipelineFlowView(nodes: nodes, selection: selection)
          .frame(width: 242)
          .padding(.trailing, 24)
          .padding(.vertical, 18)

        Divider()

        editor()
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .padding(.leading, 32)
          .padding(.vertical, 18)
          .id(selection.wrappedValue)
          .transition(.opacity.combined(with: .move(edge: .trailing)))
      }
      .overlay(alignment: .top) {
        Divider()
      }
      .animation(
        VhraseMotion.respectingReduceMotion(VhraseMotion.stateSpring, reduceMotion: reduceMotion),
        value: selection.wrappedValue
      )
    }
  }

  /// Maps each Capture setting to its one owning stage.
  var capturePipelineNodes: [PipelineFlowNode] {
    [
      PipelineFlowNode(
        id: .trigger,
        systemImage: "keyboard",
        title: "Trigger",
        detail: "\(appState.settings.hotkeyDisplay) · \(appState.settings.shortcutBehavior.title)"
      ),
      PipelineFlowNode(
        id: .listen,
        systemImage: "mic.fill",
        title: "Listen",
        detail: appState.settings.recognitionLanguage.isEmpty
          ? "Auto language" : appState.settings.recognitionLanguage
      ),
      PipelineFlowNode(
        id: .transcribe,
        systemImage: "waveform",
        title: "Transcribe",
        detail:
          "\(appState.settings.provider.title) · \(appState.settings.transcriptionMode.title)",
        badge: appState.settings.keytermList.isEmpty
          ? nil
          : "\(appState.settings.keytermList.count) preferred terms"
      ),
    ]
  }

  /// Maps finalization settings onto Correct → Enhance → Deliver without repeating Capture controls.
  var outputPipelineNodes: [PipelineFlowNode] {
    var enhancementDetails: [String] = []
    if appState.settings.includeScreenshot {
      enhancementDetails.append("Screen context")
    }
    if appState.settings.useLocalAdjustmentFallback {
      enhancementDetails.append("Local fallback")
    }
    var deliveryDetails: [String] = []
    if appState.settings.keepTranscriptOnClipboard {
      deliveryDetails.append("Kept on clipboard")
    }
    if appState.savesTranscriptHistory {
      deliveryDetails.append("Saved to history")
    }

    let replacementCount = appState.settings.replacements.count
    return [
      PipelineFlowNode(
        id: .correct,
        systemImage: "text.badge.checkmark",
        title: "Correct",
        detail: replacementCount == 0
          ? "No exact replacements"
          : "\(replacementCount) exact \(replacementCount == 1 ? "replacement" : "replacements")",
        isActive: replacementCount > 0,
        isOptional: true
      ),
      PipelineFlowNode(
        id: .enhance,
        systemImage: "wand.and.stars",
        title: "Enhance",
        detail: appState.settings.adjustWithLLM
          ? (appState.settings.adjustmentModel.isEmpty
            ? "LLM enabled" : appState.settings.adjustmentModel)
          : "Raw transcript passes through",
        badge: enhancementDetails.isEmpty
          ? nil
          : enhancementDetails.joined(separator: " · "),
        isActive: appState.settings.adjustWithLLM,
        isOptional: true
      ),
      PipelineFlowNode(
        id: .deliver,
        systemImage: "text.insert",
        title: "Deliver",
        detail: "Return to active app",
        badge: deliveryDetails.isEmpty
          ? nil
          : deliveryDetails.joined(separator: " · ")
      ),
    ]
  }

  /// Routes Capture selection to one full stage editor.
  @ViewBuilder var captureWorkflowStageEditor: some View {
    switch selectedCapturePipelineStage {
    case .trigger:
      triggerStageSettings
    case .listen:
      listeningStageSettings
    case .transcribe:
      transcriptionStageSettings
    default:
      EmptyView()
    }
  }

  /// Routes Output selection to one full finalization-stage editor.
  @ViewBuilder var outputWorkflowStageEditor: some View {
    switch selectedOutputPipelineStage {
    case .correct:
      correctionStageSettings
    case .enhance:
      enhancementStageSettings
    case .deliver:
      deliveryStageSettings
    default:
      EmptyView()
    }
  }

  /// Introduces the currently selected stage before its controls.
  func workflowStageHeader(
    _ title: String,
    description: String,
    systemImage: String
  ) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: systemImage)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(VhraseTheme.workflowAccent)
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(VhraseFont.headline)
        Text(description)
          .font(VhraseFont.caption)
          .foregroundStyle(VhraseTheme.inkSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  func settingsToggle(
    _ title: String,
    detail: String,
    isOn: Binding<Bool>
  ) -> some View {
    Toggle(isOn: isOn) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .accessibilityLabel(title)
    .accessibilityHint(detail)
  }

  func activityMetric(
    _ title: String,
    value: String,
    detail: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(value)
        .font(VhraseFont.statValue)
        .foregroundStyle(.primary)
        .contentTransition(.numericText())
      Text(title)
        .font(.callout.weight(.medium))
      Text(detail)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  var transcriptWorkspaceTitle: String {
    if hasInterruptedLiveTranscript {
      return "Interrupted transcript"
    }
    return showsLiveCapture ? "Live transcript" : "Latest transcript"
  }

  var transcriptWorkspaceSubtitle: String {
    if hasInterruptedLiveTranscript {
      return "Partial realtime text captured before the failure"
    }
    return switch appState.status {
    case .preparing:
      "Getting the microphone ready"
    case .recording:
      appState.settings.transcriptionMode == .realtime
        ? "Updates while you speak"
        : "Transcribes after you stop"
    case .transcribing:
      "Audio captured · \(appState.settings.provider.title) is working"
    case .adjusting:
      "Applying your writing preferences"
    case .idle, .completed, .failed:
      "Your most recent completed dictation"
    }
  }

  var transcriptWorkspaceText: String {
    if hasInterruptedLiveTranscript {
      return appState.liveTranscript
    }
    return switch appState.status {
    case .preparing:
      "Starting microphone…"
    case .recording:
      presentation.fullLiveTranscriptText
    case .transcribing:
      appState.liveTranscript.isEmpty
        ? "Audio captured. Waiting for \(appState.settings.provider.title) to return the transcript…"
        : appState.liveTranscript
    case .adjusting:
      appState.liveTranscript.isEmpty
        ? "Transcript received. Applying your writing preferences…"
        : appState.liveTranscript
    case .idle, .completed, .failed:
      appState.lastTranscript.isEmpty
        ? "Your next transcript will appear here." : appState.lastTranscript
    }
  }

  var transcriptWorkspaceIsPlaceholder: Bool {
    if hasInterruptedLiveTranscript {
      return false
    }
    switch appState.status {
    case .preparing, .recording, .transcribing, .adjusting:
      return appState.liveTranscript.isEmpty
    case .idle, .completed, .failed:
      return appState.lastTranscript.isEmpty
    }
  }

  var transcriptWorkspaceCopyText: String {
    hasInterruptedLiveTranscript ? appState.liveTranscript : appState.lastTranscript
  }

  var transcriptWorkspaceCopyTitle: String {
    hasInterruptedLiveTranscript ? "Copy partial" : "Copy"
  }

  var transcriptWorkspaceShowsCopyAction: Bool {
    hasInterruptedLiveTranscript || !showsLiveCapture
  }

  private var hasInterruptedLiveTranscript: Bool {
    guard !appState.liveTranscript.isEmpty else {
      return false
    }
    switch appState.status {
    case .failed, .idle:
      return true
    case .preparing, .recording, .transcribing, .adjusting, .completed:
      return false
    }
  }

  var primarySetupDiagnostic: SetupDiagnostic {
    appState.setupDiagnostics.first
      ?? SetupDiagnostic(
        id: "ready",
        title: "Ready",
        detail: "Vhrase is ready to record.",
        systemImage: "checkmark.circle.fill",
        severity: .ready
      )
  }

  var setupOverviewTitle: String {
    return switch primarySetupDiagnostic.id {
    case "ready", "opencc-s2hk":
      "Ready to dictate"
    case "screen-permission", "accessibility-permission":
      "Recording is ready"
    default:
      "Finish setup"
    }
  }

  /// Shows the least-privileged permission path for the currently selected shortcut and output behavior.
  var relevantPermissionSnapshots: [PermissionSnapshot] {
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

  var sidebarReadinessTitle: String {
    if !presentation.coreRecordingReady {
      return "Needs attention"
    }
    if !presentation.selectedShortcutReady {
      return "Shortcut needs access"
    }
    return "Ready to dictate"
  }

  var sidebarReadinessColor: Color {
    presentation.coreRecordingReady && presentation.selectedShortcutReady
      ? VhraseTheme.statusSuccess
      : VhraseTheme.statusWarning
  }

  /// Requests or opens the macOS permission required to insert finalized transcripts into other apps.
  func handleInsertionPermissionAction() {
    guard let snapshot = presentation.permissionSnapshot(.accessibility) else {
      return
    }
    appState.handlePermissionAction(snapshot)
  }

  var setupOverviewDetail: String {
    if primarySetupDiagnostic.id == "opencc-s2hk",
      let failureMessage = appState.openCCInstallationState.failureMessage
    {
      return failureMessage
    }
    return switch primarySetupDiagnostic.id {
    case "ready":
      "The selected provider and required permissions are ready."
    case "opencc-s2hk", "screen-permission", "accessibility-permission":
      "Core recording works. \(primarySetupDiagnostic.detail)"
    default:
      primarySetupDiagnostic.detail
    }
  }

  func setupDiagnosticActionTitle(_ diagnostic: SetupDiagnostic) -> String? {
    switch diagnostic.id {
    case "transcription-configuration":
      "Review Capture"
    case "selected-provider-key", "adjustment-key":
      "Add Key"
    case "microphone-permission":
      "Request Access"
    case "screen-permission":
      "Open Settings"
    case "accessibility-permission":
      if presentation.permissionSnapshot(.accessibility)?.requestedBefore == true {
        "Open Settings"
      } else if appState.settings.hotkeyPreset == .fn {
        "Enable Shortcut & Insertion"
      } else {
        "Enable Insertion"
      }
    case "opencc-s2hk":
      if appState.openCCInstallationState == .installing {
        "Installing…"
      } else if !appState.canInstallOpenCC {
        "Get Homebrew"
      } else if appState.openCCInstallationState.failureMessage != nil {
        "Retry Install"
      } else {
        "Install OpenCC"
      }
    case "ready":
      nil
    default:
      nil
    }
  }

  /// Routes the leading setup issue to the existing configuration or macOS permission action.
  func handleSetupDiagnostic(_ diagnostic: SetupDiagnostic) {
    switch diagnostic.id {
    case "transcription-configuration":
      selectedTab = .capture
    case "selected-provider-key":
      focusedSecretField =
        switch appState.settings.provider {
        case .xai:
          SecretKey.xaiAPIKey.rawValue
        case .elevenLabs:
          SecretKey.elevenLabsAPIKey.rawValue
        case .gemini:
          SecretKey.geminiAPIKey.rawValue
        }
    case "adjustment-key":
      focusedSecretField = SecretKey.llmAPIKey.rawValue
    case "microphone-permission":
      if let snapshot = presentation.permissionSnapshot(.microphone) {
        appState.handlePermissionAction(snapshot)
      } else {
        appState.setupPermissionsOnce()
      }
    case "screen-permission":
      if let snapshot = presentation.permissionSnapshot(.screenRecording) {
        appState.handlePermissionAction(snapshot)
      }
    case "accessibility-permission":
      if let snapshot = presentation.permissionSnapshot(.accessibility) {
        appState.handlePermissionAction(snapshot)
      }
    case "opencc-s2hk":
      if appState.canInstallOpenCC {
        isOpenCCInstallConfirmationPresented = true
      } else {
        appState.openHomebrewSetup()
      }
    case "ready":
      break
    default:
      break
    }
  }

  func labeledPicker<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    LabeledContent(title) {
      content()
        .frame(maxWidth: 240)
    }
  }

  func compactField(
    _ title: String,
    text: Binding<String>
  ) -> some View {
    LabeledContent(title) {
      TextField(title, text: text)
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: 360)
    }
  }

  func editorTile(
    _ title: String,
    systemImage: String,
    text: Binding<String>,
    height: CGFloat,
    instruction: String? = nil,
    placeholder: String? = nil
  ) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Label(title, systemImage: systemImage)
        .font(.subheadline.weight(.medium))

      if let instruction {
        Text(instruction)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      ZStack(alignment: .topLeading) {
        TextEditor(text: text)
          .font(.body.monospaced())
          .scrollContentBackground(.hidden)
          .accessibilityLabel(title)
          .accessibilityHint(instruction ?? "")

        if text.wrappedValue.isEmpty, let placeholder {
          Text(placeholder)
            .font(.body.monospaced())
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 5)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
      }
      .frame(minHeight: height, maxHeight: height)
      .padding(8)
      .insetField()
    }
  }

  func keyStatus(
    _ title: String,
    isReady: Bool,
    usesEnvironmentFallback: Bool
  ) -> some View {
    StatusPill(
      title: usesEnvironmentFallback
        ? "\(title) from environment"
        : (isReady ? "\(title) ready" : "\(title) missing"),
      systemImage: isReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
      color: isReady ? VhraseTheme.statusSuccess : VhraseTheme.statusWarning
    )
  }

  func permissionTile(_ snapshot: PermissionSnapshot) -> some View {
    Button {
      appState.handlePermissionAction(snapshot)
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
}

extension MainWindowView {
  var statusDetail: String {
    switch appState.status {
    case .idle:
      let presentation = self.presentation
      if !presentation.selectedProviderHasKey {
        return "Add the selected provider key before recording."
      }
      if !presentation.permissionIsReady(.microphone) {
        return "Grant Microphone access before recording."
      }
      if let transcriptionConfigurationIssue = presentation.transcriptionConfigurationIssue {
        return transcriptionConfigurationIssue
      }
      return "Ready for \(presentation.fullWorkflowSummary)."
    case .preparing:
      return "Starting the microphone and preparing \(appState.settings.provider.title)."
    case .recording:
      if appState.settings.shortcutBehavior == .holdToRecord {
        return "Listening. Release \(appState.settings.hotkeyDisplay) to transcribe."
      }
      return "Listening. Press \(appState.settings.hotkeyDisplay) again when you are done."
    case .transcribing:
      return "Transcribing with \(appState.settings.provider.title)."
    case .adjusting:
      return "Cleaning up the transcript."
    case .completed:
      return appState.lastDelivery.completionDetail
    case .failed(let message):
      return message
    }
  }

  var showsLiveCapture: Bool {
    if !appState.liveTranscript.isEmpty {
      return true
    }
    switch appState.status {
    case .preparing, .recording, .transcribing, .adjusting:
      return true
    case .idle, .completed, .failed:
      return false
    }
  }

  var filteredHistory: [TranscriptHistoryItem] {
    let query = historyQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else {
      return appState.history
    }
    return appState.history.filter { item in
      item.text.localizedCaseInsensitiveContains(query)
        || item.provider.localizedCaseInsensitiveContains(query)
        || item.transcriptionMode.localizedCaseInsensitiveContains(query)
        || item.cleanup.title.localizedCaseInsensitiveContains(query)
        || item.targetAppName?.localizedCaseInsensitiveContains(query) == true
    }
  }

  var keytermGuidance: String {
    if let issue = appState.transcriptionConfigurationIssue {
      return issue
    }
    switch (appState.settings.provider, appState.settings.transcriptionMode) {
    case (.xai, _):
      return "xAI accepts up to 100 keyterms, with at most 50 characters in each term."
    case (.gemini, _):
      return
        "Gemini accepts up to 1,000 terms; a focused list of 100 or fewer works best. Your vocabulary is shared across providers."
    case (.elevenLabs, .upload):
      return
        "ElevenLabs upload accepts up to 1,000 keyterms; using keyterms adds 20% to transcription usage."
    case (.elevenLabs, .realtime):
      return
        "ElevenLabs realtime accepts up to 50 keyterms of 20 characters each; using keyterms adds 20% to transcription usage."
    }
  }

  func handleRecordButton() {
    switch presentation.recordAction {
    case .toggleRecording:
      appState.toggleRecording()
    case .cancelRecording:
      appState.cancelRecording()
    case .openSetup:
      selectedTab = .system
    case .disabled:
      break
    }
  }

  func cancelShortcutCaptureIfNeeded() {
    guard isCapturingHotkey else {
      return
    }
    isCapturingHotkey = false
    appState.cancelShortcutCapture()
  }

  func persistedBinding<Value>(
    _ keyPath: WritableKeyPath<DictationSettings, Value>
  ) -> Binding<Value> {
    Binding(
      get: {
        appState.settings[keyPath: keyPath]
      },
      set: { value in
        appState.updateSettings { settings in
          settings[keyPath: keyPath] = value
        }
      }
    )
  }

  func apiKeyBinding(_ key: SecretKey) -> Binding<String> {
    Binding(
      get: {
        switch key {
        case .xaiAPIKey: appState.xaiAPIKey
        case .elevenLabsAPIKey: appState.elevenLabsAPIKey
        case .geminiAPIKey: appState.geminiAPIKey
        case .llmAPIKey: appState.llmAPIKey
        }
      },
      set: { value in
        appState.updateAPIKey(key, value: value)
      }
    )
  }

  /// Ends credential editing and commits any pending Keychain update.
  func finishAPIKeyEditing() {
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
