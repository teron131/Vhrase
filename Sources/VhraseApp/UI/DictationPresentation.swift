// Maps Vhrase's workflow and readiness state into consistent UI-facing copy and actions.

import Foundation
import SwiftUI

struct DictationPresentation {
  let status: AppStatus
  let settings: DictationSettings
  let providerReadiness: ProviderReadiness
  let permissions: [PermissionSnapshot]
  let liveTranscript: String
  let completion: WorkflowCompletion
  let transcriptionConfigurationIssue: String?
  /// The vocabulary limit the selected provider would reject; when it is also the configuration issue, Vocabulary owns the fix rather than Transcription.
  let vocabularyIssue: String?
  let restyleIssue: String?

  /// Validates immutable settings once so every readiness label and action uses the same result.
  init(
    status: AppStatus,
    settings: DictationSettings,
    providerReadiness: ProviderReadiness,
    permissions: [PermissionSnapshot],
    liveTranscript: String,
    completion: WorkflowCompletion = .transcript(.none)
  ) {
    self.status = status
    self.settings = settings
    self.providerReadiness = providerReadiness
    self.permissions = permissions
    self.liveTranscript = liveTranscript
    self.completion = completion
    transcriptionConfigurationIssue = TranscriptionContract.configurationIssue(in: settings)
    vocabularyIssue = TranscriptionContract.vocabularyIssue(in: settings)
    restyleIssue = settings.restyleIssue
  }

  var transcriptionNeedsAttention: Bool {
    providerReadiness != .ready
      || (transcriptionConfigurationIssue != nil
        && transcriptionConfigurationIssue != vocabularyIssue
        && transcriptionConfigurationIssue != restyleIssue)
  }

  var polishingSummary: String {
    switch settings.afterTranscription {
    case .off:
      "Raw transcripts"
    case .refine:
      "Refine · \(PolishPreset.matching(settings.polishPreferences)?.title ?? "Custom")"
    case .restyle:
      "Restyle · \(settings.polishStyle.title)"
    }
  }

  var coreRecordingReady: Bool {
    providerReadiness == .ready
      && permissions.isReady(.microphone)
      && transcriptionConfigurationIssue == nil
  }

  var selectedShortcutReady: Bool {
    settings.hotkeyPreset != .fn
      || permissions.isReady(.inputMonitoring)
      || permissions.isReady(.accessibility)
  }

  /// `nil` once Accessibility is granted.
  var insertionPermissionActionTitle: String? {
    guard let snapshot = permissions.snapshot(for: .accessibility), !snapshot.state.isReady else {
      return nil
    }
    return snapshot.requestedBefore ? "Open Accessibility" : "Allow Accessibility"
  }

  var workflowControlsAreDisabled: Bool {
    !status.canStartRecording
  }

  var compactWorkflowSummary: String {
    "\(settings.provider.title) \(settings.transcriptionModeTitle.lowercased()) · \(settings.hotkeyDisplay)"
  }

  var displayStatusTitle: String {
    switch status {
    case .idle:
      if providerReadiness != .ready || !permissions.isReady(.microphone) {
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

  /// `nil` leaves the bar neutral while setup is unfinished.
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
      } else if !permissions.isReady(.microphone) {
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
    if !permissions.isReady(.microphone) {
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
    if !permissions.isReady(.microphone) {
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
    if !permissions.isReady(.microphone) {
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
      let cleanup = settings.dictationPolishOperation?.title ?? "Raw"
      return
        "\(settings.provider.title) \(settings.transcriptionModeTitle.lowercased()) · \(cleanup) · \(ShortcutGestureInterpreter.summary(settings.shortcutGestures))"
    case .full:
      return
        "\(settings.hotkeyDisplay) · \(ShortcutGestureInterpreter.summary(settings.shortcutGestures))"
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

  static func historyMetadata(
    _ item: TranscriptHistoryItem,
    relativeTo date: Date? = Date()
  ) -> String {
    let target = item.targetAppName.map { "→ \($0)" }
    let dateLabel = date.map { relativeDateLabel(for: item.createdAt, relativeTo: $0) }
    return [dateLabel, item.provider, item.transcriptionMode, item.cleanupTitle, target]
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
      ? "Recording audio for local transcription…" : "Recording audio for upload transcription…"
  }

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
    case .textRestyled: "Text restyled"
    }
  }

  var completionDetail: String {
    switch self {
    case .transcript(let delivery): delivery.completionDetail
    case .textRestyled(let style):
      "Restyled with \(style.title). Use Command-Z in the target app to undo."
    }
  }

  var completionSystemImage: String {
    switch self {
    case .transcript(let delivery): delivery.completionSystemImage
    case .textRestyled: "wand.and.stars"
    }
  }
}
