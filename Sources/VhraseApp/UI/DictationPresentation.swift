// Maps Vhrase's workflow and readiness state into consistent UI-facing copy and actions.

import Foundation
import SwiftUI

/// Owns reusable display policy shared by Vhrase's compact and full-window UI surfaces.
struct DictationPresentation {
  let status: AppStatus
  let settings: DictationSettings
  let providerReadiness: ProviderReadiness
  let permissions: [PermissionSnapshot]
  let liveTranscript: String
  let recordingElapsedSeconds: Int
  let completion: WorkflowCompletion
  let transcriptionConfigurationIssue: String?

  /// Validates immutable settings once so every readiness label and action uses the same result.
  init(
    status: AppStatus,
    settings: DictationSettings,
    providerReadiness: ProviderReadiness,
    permissions: [PermissionSnapshot],
    liveTranscript: String,
    recordingElapsedSeconds: Int,
    completion: WorkflowCompletion = .transcript(.none)
  ) {
    self.status = status
    self.settings = settings
    self.providerReadiness = providerReadiness
    self.permissions = permissions
    self.liveTranscript = liveTranscript
    self.recordingElapsedSeconds = recordingElapsedSeconds
    self.completion = completion
    transcriptionConfigurationIssue = TranscriptionContract.configurationIssue(in: settings)
  }

  var coreRecordingReady: Bool {
    providerReadiness == .ready
      && permissionIsReady(.microphone)
      && transcriptionConfigurationIssue == nil
  }

  /// Reports whether the selected shortcut can receive global key events with the current permissions.
  var selectedShortcutReady: Bool {
    settings.hotkeyPreset != .fn
      || permissionIsReady(.inputMonitoring)
      || permissionIsReady(.accessibility)
  }

  /// Offers the Accessibility action that lets finalized text return to the originating app.
  var insertionPermissionActionTitle: String? {
    guard let snapshot = permissionSnapshot(.accessibility), !snapshot.state.isReady else {
      return nil
    }
    return snapshot.requestedBefore ? "Open Accessibility" : "Enable Insertion"
  }

  var workflowControlsAreDisabled: Bool {
    !status.canStartRecording
  }

  var elapsedTime: String {
    let minutes = recordingElapsedSeconds / 60
    let seconds = recordingElapsedSeconds % 60
    return String(format: "%d:%02d", minutes, seconds)
  }

  var compactWorkflowSummary: String {
    "\(settings.provider.title) \(settings.transcriptionModeTitle.lowercased()) · \(settings.hotkeyDisplay)"
  }

  var displayStatusTitle: String {
    switch status {
    case .idle:
      if providerReadiness != .ready || !permissionIsReady(.microphone) {
        "Needs setup"
      } else if transcriptionConfigurationIssue != nil {
        "Check settings"
      } else if !selectedShortcutReady {
        "Shortcut setup"
      } else {
        "Ready"
      }
    case .preparing:
      "Starting"
    case .recording:
      "Listening"
    case .transcribing:
      "Transcribing"
    case .adjusting:
      "Cleaning up"
    case .completed:
      completion.completionTitle
    case .failed:
      "Couldn't finish"
    }
  }

  var statusTint: Color {
    switch status {
    case .recording:
      VhraseTheme.statusRecording
    case .completed:
      completion == .transcript(.none) ? VhraseTheme.statusWarning : VhraseTheme.statusSuccess
    case .failed:
      VhraseTheme.statusFailure
    case .preparing, .transcribing, .adjusting:
      VhraseTheme.statusProcessing
    case .idle:
      coreRecordingReady && selectedShortcutReady
        ? VhraseTheme.inkSecondary
        : VhraseTheme.statusWarning
    }
  }

  /// Fills the mic bar: orange when ready, red while the microphone is live, violet while Vhrase works, and neutral until setup is complete.
  var micBarTint: Color? {
    switch status {
    case .preparing, .recording:
      VhraseTheme.statusRecording
    case .transcribing, .adjusting:
      VhraseTheme.statusProcessing
    case .failed:
      VhraseTheme.statusFailure
    case .completed:
      VhraseTheme.accent
    case .idle:
      coreRecordingReady && transcriptionConfigurationIssue == nil ? VhraseTheme.accent : nil
    }
  }

  var statusSystemImage: String {
    switch status {
    case .failed:
      "exclamationmark.triangle.fill"
    case .preparing:
      "mic.badge.plus"
    case .recording:
      "waveform.circle.fill"
    case .transcribing, .adjusting:
      "clock.fill"
    case .completed:
      "checkmark.circle.fill"
    case .idle:
      if let providerSetupSystemImage {
        providerSetupSystemImage
      } else if !permissionIsReady(.microphone) {
        "mic.slash.fill"
      } else if transcriptionConfigurationIssue != nil {
        "slider.horizontal.3"
      } else if !selectedShortcutReady {
        "keyboard.badge.ellipsis"
      } else {
        "checkmark.circle"
      }
    }
  }

  var statusMessage: String? {
    if case .failed(let message) = status {
      return message
    }
    if !isRecording {
      switch providerReadiness {
      case .ready:
        break
      case .missingAPIKey:
        return "Add \(settings.provider.title) API key in System before recording."
      case .missingLocalModel:
        return "Download the \(settings.provider.title) model before recording."
      }
    }
    if !permissionIsReady(.microphone), status.canStartRecording {
      return "Grant Microphone access before recording."
    }
    if let transcriptionConfigurationIssue, status.canStartRecording {
      return transcriptionConfigurationIssue
    }
    return nil
  }

  var statusMessageIcon: String {
    if case .failed = status {
      return "exclamationmark.triangle"
    }
    if !permissionIsReady(.microphone) {
      return "mic.slash"
    }
    if transcriptionConfigurationIssue != nil {
      return "slider.horizontal.3"
    }
    return providerReadiness == .missingLocalModel ? "arrow.down.circle" : "key"
  }

  var recordAction: RecordAction {
    if isPreparing {
      return .cancelRecording
    }
    if isRecording {
      return .toggleRecording
    }
    guard status.canStartRecording else {
      return .disabled
    }
    return coreRecordingReady ? .toggleRecording : .openSetup
  }

  var recordButtonSystemImage: String {
    if isPreparing {
      return "xmark"
    }
    if isRecording {
      return "stop.fill"
    }
    if let providerSetupSystemImage {
      return providerSetupSystemImage
    }
    if !permissionIsReady(.microphone) {
      return "mic.slash.fill"
    }
    if transcriptionConfigurationIssue != nil {
      return "slider.horizontal.3"
    }
    return "mic.fill"
  }

  var recordButtonTitle: String {
    if isPreparing {
      return "Cancel"
    }
    if isRecording {
      return "Stop and Transcribe"
    }
    switch providerReadiness {
    case .ready:
      break
    case .missingAPIKey:
      return "Add \(settings.provider.title) Key"
    case .missingLocalModel:
      return "Download Model"
    }
    if !permissionIsReady(.microphone) {
      return "Set Up Microphone"
    }
    if transcriptionConfigurationIssue != nil {
      return "Review Settings"
    }
    if status.isProcessing {
      return "Processing…"
    }
    return "Start Recording"
  }

  func recordButtonSubtitle(style: RecordSubtitleStyle) -> String {
    if isPreparing {
      return "Starting microphone…"
    }
    switch (providerReadiness, style) {
    case (.ready, _):
      break
    case (.missingAPIKey, .compact):
      return "Keys are saved locally"
    case (.missingAPIKey, .full):
      return "Keys save locally"
    case (.missingLocalModel, .compact):
      return "One-time download, then works offline"
    case (.missingLocalModel, .full):
      return "Runs on this Mac"
    }
    if !permissionIsReady(.microphone) {
      return "Microphone permission is required"
    }
    if let transcriptionConfigurationIssue {
      return transcriptionConfigurationIssue
    }
    if status.isProcessing {
      switch style {
      case .compact:
        return
          "\(settings.provider.title) \(settings.transcriptionModeTitle.lowercased()) is processing"
      case .full:
        return "\(settings.provider.title) is working"
      }
    }
    switch style {
    case .compact:
      let cleanup = settings.adjustWithLLM ? "LLM cleanup" : "Raw"
      return
        "\(settings.provider.title) \(settings.transcriptionModeTitle.lowercased()) · \(cleanup) · \(ShortcutGestureInterpreter.summary)"
    case .full:
      return "\(settings.hotkeyDisplay) · \(ShortcutGestureInterpreter.summary)"
    }
  }

  var compactLiveTranscriptText: String {
    if !liveTranscript.isEmpty {
      return liveTranscript
    }
    return recordingPlaceholderText
  }

  var fullLiveTranscriptText: String {
    if !liveTranscript.isEmpty {
      return liveTranscript
    }
    if isRecording {
      return recordingPlaceholderText
    }
    return "Live recording details will appear here while you speak."
  }

  func permissionIsReady(_ permission: AppPermission) -> Bool {
    permissionSnapshot(permission)?.state.isReady ?? false
  }

  func permissionSnapshot(_ permission: AppPermission) -> PermissionSnapshot? {
    permissions.first { $0.permission == permission }
  }

  /// Summarizes a saved transcript's source and cleanup without depending on the current workflow.
  static func historyMetadata(
    _ item: TranscriptHistoryItem,
    relativeTo date: Date? = Date()
  ) -> String {
    let target = item.targetAppName.map { "→ \($0)" }
    let dateLabel = date.map { relativeDateLabel(for: item.createdAt, relativeTo: $0) }
    return [dateLabel, item.provider, item.transcriptionMode, item.cleanup.title, target]
      .compactMap(\.self)
      .joined(separator: " · ")
  }

  private var isRecording: Bool {
    if case .recording = status {
      return true
    }
    return false
  }

  private var isPreparing: Bool {
    if case .preparing = status {
      return true
    }
    return false
  }

  private var recordingPlaceholderText: String {
    if settings.transcriptionMode == .realtime {
      return "Listening for realtime transcript…"
    }
    return settings.provider.location == .local
      ? "Recording audio for on-device transcription…" : "Recording audio for upload transcription…"
  }

  /// Marks the missing credential or model with the icon its setup action uses.
  private var providerSetupSystemImage: String? {
    switch providerReadiness {
    case .ready: nil
    case .missingAPIKey: "key.fill"
    case .missingLocalModel: "arrow.down.circle.fill"
    }
  }

  private static func relativeDateLabel(
    for createdAt: Date,
    relativeTo date: Date
  ) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: createdAt, relativeTo: date)
  }
}

enum RecordAction: Equatable {
  case toggleRecording
  case cancelRecording
  case openSetup
  case disabled
}

enum RecordSubtitleStyle {
  case compact
  case full
}

extension TranscriptDelivery {
  var completionTitle: String {
    switch self {
    case .pasteCommandSent:
      "Paste sent"
    case .copied:
      "Copied"
    case .none:
      "Saved"
    }
  }

  var completionDetail: String {
    switch self {
    case .pasteCommandSent(let clipboardRetained):
      clipboardRetained
        ? "The paste command was sent, and the transcript remains on the clipboard."
        : "The paste command was sent without keeping the transcript on the clipboard."
    case .copied:
      "The transcript was copied to the clipboard."
    case .none:
      "The transcript was saved to history, but clipboard delivery failed."
    }
  }

  var completionSystemImage: String {
    switch self {
    case .pasteCommandSent:
      "checkmark.circle.fill"
    case .copied:
      "doc.on.clipboard.fill"
    case .none:
      "exclamationmark.triangle.fill"
    }
  }
}

extension WorkflowCompletion {
  var completionTitle: String {
    switch self {
    case .transcript(let delivery): delivery.completionTitle
    case .textPolished: "Text polished"
    }
  }

  var completionDetail: String {
    switch self {
    case .transcript(let delivery): delivery.completionDetail
    case .textPolished:
      "The focused text was polished and replaced. Use Command-Z in the target app to undo."
    }
  }

  var completionSystemImage: String {
    switch self {
    case .transcript(let delivery): delivery.completionSystemImage
    case .textPolished: "wand.and.stars"
    }
  }
}
