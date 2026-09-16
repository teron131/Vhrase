// Coordinates Vhrase's observable application state and user-triggered workflows.

import AppKit
import Foundation
import OSLog

enum OpenCCInstallationState: Equatable {
  case idle
  case installing
  case installed
  case failed(String)

  var failureMessage: String? {
    guard case .failed(let message) = self else {
      return nil
    }
    return message
  }
}

@MainActor
final class AppState: ObservableObject {
  private static let developmentEnvironmentFileArgument = "--development-environment-file"
  private static let workflowOutcomeDisplayDuration = Duration.seconds(4)

  @Published var status: AppStatus = .idle {
    didSet {
      guard status != oldValue else { return }
      scheduleWorkflowOutcomeDismissal(for: status)
      let phase: String
      switch status {
      case .idle: phase = "idle"
      case .preparing: phase = "preparing"
      case .recording: phase = "recording"
      case .transcribing: phase = "transcribing"
      case .adjusting: phase = "adjusting"
      case .completed: phase = "completed"
      case .failed: phase = "failed"
      }
      logger.notice("Workflow attempt=\(self.recordingSequence) phase=\(phase, privacy: .public)")
    }
  }
  @Published var settings: DictationSettings
  @Published var xaiAPIKey: String
  @Published var elevenLabsAPIKey: String
  @Published var geminiAPIKey: String
  @Published var llmAPIKey: String
  @Published private(set) var unsavedAPIKeys: Set<SecretKey> = []
  @Published private(set) var keychainReadNotice = ""
  @Published var lastTranscript = ""
  @Published var lastRecognizedTranscript = ""
  @Published var lastTranscriptionSeconds: Double?
  @Published var liveTranscript = ""
  @Published var recordingLevel = 0.0
  let audioInputPreview = AudioInputPreview()
  @Published var recordingElapsedSeconds = 0
  @Published var permissions: [PermissionSnapshot] = []
  @Published var history: [TranscriptHistoryItem] = []
  @Published private(set) var activityDays: [DictationActivityDay] = []
  @Published var savesTranscriptHistory = true
  @Published var lastAdjustmentWarning = ""
  @Published var lastDelivery: TranscriptDelivery = .none
  @Published var targetAppLabel = ""
  @Published var customizationNotice = ""
  @Published var openCCInstallationState = OpenCCInstallationState.idle
  @Published private(set) var isCheckingLLMModelAccess = false

  /// Counts saved transcripts created today for the activity summaries across UI surfaces.
  var transcriptsTodayCount: Int {
    history.filter { Calendar.current.isDateInToday($0.createdAt) }.count
  }

  private let settingsStore = SettingsStore()
  private let historyStore = TranscriptHistoryStore()
  private let activityStore = DictationActivityStore()
  private let apiKeys: APIKeyStore
  private let customizationTransfer = CustomizationTransfer()
  private let inserter = TextInsertion()
  private let permissionManager = PermissionManager()
  private let appContext = AppContext()
  private let openCCInstaller = OpenCCInstaller()
  private let hotkeyManager = GlobalHotkeyManager()
  private let fnHotkeyManager = FnHotkeyManager()
  private var recorder: AudioRecorder?
  private let logger = Logger(subsystem: "local.codex.Vhrase", category: "Dictation")
  private var recordingSequence = 0
  private var realtimeSession: RealtimeTranscriptionSession?
  private var recordingTask: Task<Void, Never>?
  private var recordingTimer: Timer?
  private var workflowOutcomeDismissTask: Task<Void, Never>?
  private var recordingID: UUID?
  private var recordingTargetApp: FrontmostApp?
  private var recordingConfiguration: RecordingConfiguration?
  private var recordingSpeechPresence: SpeechPresenceGate?
  private var processingAudioURL: URL?
  private var isShortcutCaptureActive = false
  private var lastHotkeyPressDate: Date?
  private var apiKeySaveTask: Task<Void, Never>?
  private var pendingAPIKeySaves: Set<SecretKey> = []
  private var editedAPIKeys: Set<SecretKey> = []
  private var shouldLoadSavedAPIKeysAfterLaunch = false

  init() {
    let developmentEnvironmentFileURL = Self.developmentEnvironmentFileURL(
      arguments: CommandLine.arguments
    )
    var credentialNotices: [String] = []
    var environment = ProcessInfo.processInfo.environment
    do {
      environment = try APIKeyStore.zshrcEnvironment(baseEnvironment: environment)
    } catch {
      credentialNotices.append(
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
        credentialNotices.append(
          "Could not read development credentials: \(error.localizedDescription)"
        )
      }
    }
    let apiKeys = APIKeyStore(environment: environment)
    self.apiKeys = apiKeys
    settings = settingsStore.load()
    xaiAPIKey = ""
    elevenLabsAPIKey = ""
    geminiAPIKey = ""
    llmAPIKey = ""
    shouldLoadSavedAPIKeysAfterLaunch = developmentEnvironmentFileURL == nil
    history = historyStore.load()
    activityDays = activityStore.load()
    savesTranscriptHistory = historyStore.savesHistory
    lastTranscript = history.first?.text ?? ""
    AudioRecorder.removeAbandonedRecordings()
    customizationNotice = credentialNotices.joined(separator: " ")
    refreshPermissions()
    registerHotkey()
  }

  /// Loads Keychain credentials after the menu-bar lifecycle is established without blocking AppKit launch.
  func loadSavedAPIKeysAfterLaunch() {
    guard shouldLoadSavedAPIKeysAfterLaunch else {
      return
    }
    shouldLoadSavedAPIKeysAfterLaunch = false

    let apiKeys = apiKeys
    let keys = SecretKey.allCases.filter { !editedAPIKeys.contains($0) }
    Task {
      let loaded = await Task.detached {
        var values: [SecretKey: String] = [:]
        var notices: [String] = []

        for key in keys {
          do {
            values[key] = try apiKeys.savedValue(for: key)
          } catch {
            notices.append(error.localizedDescription)
          }
        }
        return (values: values, notices: notices)
      }.value

      for key in keys where !editedAPIKeys.contains(key) {
        guard let value = loaded.values[key] else { continue }
        self[keyPath: apiKeyPath(for: key)] = value
      }

      let keychainNotice = loaded.notices.joined(separator: " ")
      keychainReadNotice = keychainNotice
      if !keychainNotice.isEmpty {
        customizationNotice = [customizationNotice, keychainNotice]
          .filter { !$0.isEmpty }
          .joined(separator: " ")
      }
    }
  }

  /// Retries inaccessible saved keys without a password dialog or overwriting credentials edited during this session.
  func retryLoadingAPIKeys() {
    shouldLoadSavedAPIKeysAfterLaunch = true
    loadSavedAPIKeysAfterLaunch()
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

  var effectiveXAIAPIKey: String {
    effectiveAPIKey(.xaiAPIKey)
  }

  var effectiveElevenLabsAPIKey: String {
    effectiveAPIKey(.elevenLabsAPIKey)
  }

  var effectiveGeminiAPIKey: String {
    effectiveAPIKey(.geminiAPIKey)
  }

  var effectiveLLMAPIKey: String {
    effectiveAPIKey(.llmAPIKey)
  }

  var effectiveLLMBaseURL: String {
    apiKeys.effectiveLLMBaseURL(savedValue: settings.adjustmentBaseURL)
  }

  var usesEnvironmentLLMBaseURL: Bool {
    apiKeys.usesEnvironmentLLMBaseURL
  }

  /// Creates the shared UI projection from the current application state.
  var presentation: DictationPresentation {
    DictationPresentation(
      status: status,
      settings: settings,
      xaiAPIKey: effectiveXAIAPIKey,
      elevenLabsAPIKey: effectiveElevenLabsAPIKey,
      permissions: permissions,
      liveTranscript: liveTranscript,
      recordingElapsedSeconds: recordingElapsedSeconds,
      delivery: lastDelivery,
      geminiAPIKey: effectiveGeminiAPIKey
    )
  }

  func usesEnvironmentFallback(for key: SecretKey) -> Bool {
    apiKeys.usesEnvironmentFallback(
      for: key,
      savedValue: self[keyPath: apiKeyPath(for: key)]
    )
  }

  var isRecording: Bool {
    if case .recording = status {
      return true
    }
    return false
  }

  var setupDiagnostics: [SetupDiagnostic] {
    SetupDiagnostics(
      settings: settings,
      xaiAPIKey: effectiveXAIAPIKey,
      elevenLabsAPIKey: effectiveElevenLabsAPIKey,
      llmAPIKey: effectiveLLMAPIKey,
      permissions: permissions,
      chineseConversionIsAvailable: ChineseTextConverter.isAvailable,
      geminiAPIKey: effectiveGeminiAPIKey
    ).build()
  }

  var canInstallOpenCC: Bool {
    OpenCCInstaller.isHomebrewAvailable
  }

  /// Installs OpenCC after explicit UI confirmation and refreshes the computed setup diagnostics.
  func installOpenCC() {
    guard openCCInstallationState != .installing else {
      return
    }

    openCCInstallationState = .installing
    customizationNotice = "Installing OpenCC with Homebrew…"
    let installer = openCCInstaller
    Task {
      do {
        try await installer.install()
        guard ChineseTextConverter.isAvailable else {
          throw NSError(
            domain: "Vhrase.OpenCCInstaller",
            code: 1,
            userInfo: [
              NSLocalizedDescriptionKey:
                "Homebrew completed, but the OpenCC executable was not found."
            ]
          )
        }
        openCCInstallationState = .installed
        customizationNotice = "OpenCC installed. New transcripts will use s2hk conversion."
      } catch {
        openCCInstallationState = .failed(error.localizedDescription)
        customizationNotice = error.localizedDescription
      }
    }
  }

  /// Opens Homebrew's setup page when OpenCC cannot yet be installed from the app.
  func openHomebrewSetup() {
    guard let url = URL(string: "https://brew.sh") else {
      return
    }
    NSWorkspace.shared.open(url)
  }

  var transcriptionConfigurationIssue: String? {
    do {
      try TranscriptionContract.validate(settings: settings)
      return nil
    } catch {
      return error.localizedDescription
    }
  }

  func toggleRecording() {
    switch status {
    case .preparing:
      cancelRecording()
    case .recording:
      beginStopAndProcess()
    case .idle, .completed, .failed:
      beginRecording()
    case .transcribing, .adjusting:
      break
    }
  }

  /// Cancels microphone startup or active capture without sending audio to a provider.
  func cancelRecording() {
    guard status == .preparing || status == .recording else {
      return
    }

    recordingID = nil
    recordingTask?.cancel()
    recordingTask = nil
    realtimeSession?.cancel()
    realtimeSession = nil
    recorder?.cancel()
    recorder = nil
    stopRecordingTimer()
    clearRecordingContext()
    liveTranscript = ""
    status = .idle
    customizationNotice = "Recording cancelled."
  }

  /// Clears completed or failed feedback without changing an active workflow.
  func dismissWorkflowOutcome() {
    switch status {
    case .completed, .failed:
      status = .idle
    case .idle, .preparing, .recording, .transcribing, .adjusting:
      break
    }
  }

  /// Owns the lifetime of transient outcomes so the model and recorder HUD return to idle together.
  private func scheduleWorkflowOutcomeDismissal(for outcome: AppStatus) {
    workflowOutcomeDismissTask?.cancel()
    workflowOutcomeDismissTask = nil

    switch outcome {
    case .completed, .failed:
      break
    case .idle, .preparing, .recording, .transcribing, .adjusting:
      return
    }

    workflowOutcomeDismissTask = Task { [weak self] in
      do {
        try await Task.sleep(for: Self.workflowOutcomeDisplayDuration)
      } catch {
        return
      }
      guard let self, self.status == outcome else { return }
      self.workflowOutcomeDismissTask = nil
      self.dismissWorkflowOutcome()
    }
  }

  func handleHotkeyPressed() {
    guard !isShortcutCaptureActive, !shouldIgnoreDuplicateHotkeyPress() else {
      logger.notice("Shortcut press ignored during capture or debounce")
      return
    }

    customizationNotice = "Shortcut \(settings.hotkeyDisplay) pressed."
    logger.notice(
      "Shortcut pressed behavior=\(self.settings.shortcutBehavior.rawValue, privacy: .public)")
    performShortcutAction(
      settings.shortcutBehavior.action(for: .pressed, status: status)
    )
  }

  func handleHotkeyReleased() {
    logger.notice("Shortcut released")
    performShortcutAction(
      settings.shortcutBehavior.action(for: .released, status: status)
    )
  }

  /// Saves only explicitly edited credentials so an unrelated field cannot erase an unread Keychain item.
  private func saveAPIKeys(_ keys: Set<SecretKey>) {
    guard !keys.isEmpty else {
      return
    }
    var failures: [String] = []
    for key in keys {
      do {
        try apiKeys.save(self[keyPath: apiKeyPath(for: key)], for: key)
        unsavedAPIKeys.remove(key)
      } catch {
        unsavedAPIKeys.insert(key)
        failures.append(error.localizedDescription)
      }
    }
    customizationNotice =
      failures.isEmpty
      ? "API key changes saved in macOS Keychain."
      : failures.joined(separator: " ") + " Unsaved changes apply only for this session."
  }

  /// Retries explicit credential edits without opening a system authentication dialog.
  func retrySavingAPIKeys() {
    saveAPIKeys(unsavedAPIKeys)
  }

  /// Updates one editable credential and debounces its Keychain write for 500 milliseconds.
  func updateAPIKey(_ key: SecretKey, value: String) {
    let path = apiKeyPath(for: key)
    guard value != self[keyPath: path] else {
      return
    }

    self[keyPath: path] = value

    pendingAPIKeySaves.insert(key)
    editedAPIKeys.insert(key)
    unsavedAPIKeys.insert(key)
    apiKeySaveTask?.cancel()
    apiKeySaveTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(nanoseconds: 500_000_000)
      } catch {
        return
      }
      guard !Task.isCancelled else {
        return
      }
      self?.savePendingAPIKeys()
    }
  }

  /// Flushes credentials edited on a disappearing configuration surface.
  func flushPendingAPIKeySave() {
    guard apiKeySaveTask != nil || !pendingAPIKeySaves.isEmpty else {
      return
    }
    apiKeySaveTask?.cancel()
    savePendingAPIKeys()
  }

  func updateSettings(_ update: (inout DictationSettings) -> Void) {
    let previousSettings = settings
    update(&settings)
    if !settings.provider.availableModes.contains(settings.transcriptionMode) {
      settings.transcriptionMode = .upload
      customizationNotice = "Gemini transcribes after you stop recording. Switched to Upload."
    }
    guard settings != previousSettings else {
      return
    }
    persistSettings(previous: previousSettings)
  }

  func beginShortcutCapture() {
    isShortcutCaptureActive = true
    customizationNotice = "Listening for a shortcut. Press Esc to cancel."
  }

  func setCustomShortcut(_ hotkey: CustomHotkey) {
    isShortcutCaptureActive = false
    updateSettings { settings in
      settings.hotkeyPreset = .custom
      settings.customHotkey = hotkey
    }
    customizationNotice = "STT shortcut set to \(hotkey.display)."
  }

  func setFnShortcut() {
    isShortcutCaptureActive = false
    updateSettings { settings in
      settings.hotkeyPreset = .fn
      settings.customHotkey = nil
    }
    customizationNotice = "STT shortcut set to Fn/Globe."
  }

  func cancelShortcutCapture() {
    isShortcutCaptureActive = false
    customizationNotice = "Shortcut capture cancelled."
  }

  func rejectShortcutCapture(_ message: String) {
    customizationNotice = message
  }

  /// Clears a transient action message without dismissing a newer replacement.
  func dismissCustomizationNotice(_ notice: String) {
    guard customizationNotice == notice else {
      return
    }
    customizationNotice = ""
  }

  func disableShortcut() {
    updateSettings { settings in
      settings.hotkeyPreset = .disabled
      settings.customHotkey = nil
    }
    customizationNotice = "STT shortcut disabled."
  }

  func refreshPermissions() {
    permissions = permissionManager.snapshots()
    fnHotkeyManager.refreshAuthorization()
  }

  func requestPermission(_ permission: AppPermission) {
    Task {
      await permissionManager.request(permission)
      refreshPermissions()
    }
  }

  func setupPermissionsOnce() {
    Task {
      await permissionManager.setupPermissions()
      refreshPermissions()
      customizationNotice =
        "Microphone setup started. Optional permissions are requested when you enable their features."
    }
  }

  func openPermissionSettings(_ permission: AppPermission) {
    permissionManager.openSettings(for: permission)
  }

  func handlePermissionAction(_ snapshot: PermissionSnapshot) {
    if snapshot.state.isReady {
      openPermissionSettings(snapshot.permission)
    } else {
      requestPermission(snapshot.permission)
    }
  }

  func copyHistoryItem(_ item: TranscriptHistoryItem) {
    do {
      try inserter.copy(item.text)
      customizationNotice = "Transcript copied."
    } catch {
      customizationNotice = error.localizedDescription
    }
  }

  func copyLastTranscript() {
    guard !lastTranscript.isEmpty else {
      return
    }
    do {
      try inserter.copy(lastTranscript)
      customizationNotice = "Last transcript copied."
    } catch {
      customizationNotice = error.localizedDescription
    }
  }

  func deleteHistoryItem(_ item: TranscriptHistoryItem) {
    history = historyStore.remove(item, from: history)
    synchronizeLatestTranscriptWithHistory()
  }

  func clearHistory() {
    historyStore.clear()
    history = []
    synchronizeLatestTranscriptWithHistory()
  }

  /// Controls whether future completed dictations are retained without deleting existing history.
  func updateTranscriptHistorySaving(_ isEnabled: Bool) {
    historyStore.setSavingEnabled(isEnabled)
    savesTranscriptHistory = isEnabled
  }

  /// Prevents a deleted history item from remaining exposed as the recoverable latest transcript.
  private func synchronizeLatestTranscriptWithHistory() {
    let latestTranscript = history.first?.text ?? ""
    guard latestTranscript != lastTranscript else {
      return
    }

    lastTranscript = latestTranscript
    lastDelivery = .none
    lastAdjustmentWarning = ""
    if status == .completed {
      status = .idle
    }
  }

  /// Releases active capture resources and removes any recording owned by an in-flight transcription before app exit.
  func prepareForTermination() {
    flushPendingAPIKeySave()
    recordingID = nil
    recordingTask?.cancel()
    recordingTask = nil
    realtimeSession?.cancel()
    realtimeSession = nil
    recorder?.cancel()
    recorder = nil
    stopRecordingTimer()
    if let processingAudioURL {
      try? FileManager.default.removeItem(at: processingAudioURL)
      self.processingAudioURL = nil
    }
    AudioRecorder.removeAbandonedRecordings()
  }

  func runDemoDictation() {
    guard status.canStartRecording else {
      return
    }

    status = .transcribing
    Task {
      await runDemoDictationPipeline()
    }
  }

  func exportCustomization() {
    do {
      if try customizationTransfer.export(settings) {
        customizationNotice = "Customization exported."
      }
    } catch {
      customizationNotice = "Export failed: \(error.localizedDescription)"
    }
  }

  func importCustomization() {
    do {
      switch try customizationTransfer.importSettings(replacing: settings) {
      case .dismissed:
        break
      case .reviewCancelled:
        customizationNotice = "Customization import cancelled."
      case .imported(let importedSettings):
        let previousSettings = settings
        settings = importedSettings
        persistSettings(previous: previousSettings)
        customizationNotice = "Customization imported."
      }
    } catch {
      customizationNotice = "Import failed: \(error.localizedDescription)"
    }
  }

  func checkLLMModelAccess() {
    guard !isCheckingLLMModelAccess else {
      return
    }
    let apiKey = effectiveLLMAPIKey
    guard !apiKey.isEmpty else {
      customizationNotice = "Add LLM API key before checking model access."
      return
    }

    let model = settings.adjustmentModel.trimmingCharacters(in: .whitespacesAndNewlines)
    let baseURL = effectiveLLMBaseURL
    isCheckingLLMModelAccess = true
    customizationNotice = "Checking LLM model: \(model)…"
    Task {
      defer { isCheckingLLMModelAccess = false }
      do {
        try await LLMModelAccessClient(
          apiKey: apiKey,
          baseURL: baseURL
        )
        .checkModel(model)
        customizationNotice = "LLM model ready: \(model)."
      } catch {
        customizationNotice = "LLM model check failed for \(model): \(error.localizedDescription)"
      }
    }
  }

  private func beginRecording() {
    guard status.canStartRecording else {
      return
    }

    audioInputPreview.stop()
    recordingSequence += 1
    logger.notice(
      "Begin attempt=\(self.recordingSequence) provider=\(self.settings.provider.rawValue, privacy: .public) mode=\(self.settings.transcriptionMode.rawValue, privacy: .public)"
    )
    let id = UUID()
    let recorder = AudioRecorder()
    recordingID = id
    self.recorder = recorder
    status = .preparing
    recordingTask = Task { [weak self] in
      await self?.startRecording(
        id: id,
        recorder: recorder
      )
    }
  }

  private func startRecording(
    id: UUID,
    recorder: AudioRecorder
  ) async {
    let configuration = currentRecordingConfiguration()
    recordingConfiguration = configuration
    recordingTargetApp = appContext.targetApp()
    targetAppLabel = recordingTargetApp?.name ?? ""
    resetLiveRecordingState()
    let speechPresence = SpeechPresenceGate()
    recordingSpeechPresence = speechPresence
    var session: RealtimeTranscriptionSession?
    do {
      try validateRecordingPermissions()
      try validateSelectedProvider(configuration)
      let startedSession = try startRealtimeSessionIfNeeded(
        configuration: configuration,
        recordingID: id
      )
      session = startedSession
      try ensureCurrentRecording(id)
      realtimeSession = startedSession
      try await recorder.start(settings: configuration.settings) { chunk in
        speechPresence.observe(level: chunk.level)
        startedSession?.sendAudioChunk(chunk.data)
        Task { @MainActor in
          guard self.recordingID == id else {
            return
          }
          self.recordingLevel = chunk.level
        }
      } onFailure: { [weak self] error in
        guard let self, self.recordingID == id else { return }
        self.cancelRecording()
        self.status = .failed(error.localizedDescription)
      }
      try ensureCurrentRecording(id)
      recordingTask = nil
      startRecordingTimer()
      status = .recording
    } catch is CancellationError {
      session?.cancel()
      recorder.cancel()
      finishRecordingStartup(
        id: id,
        error: nil
      )
    } catch {
      let failure = error as NSError
      logger.error("Startup failed domain=\(failure.domain, privacy: .public) code=\(failure.code)")
      session?.cancel()
      recorder.cancel()
      finishRecordingStartup(
        id: id,
        error: error
      )
    }
  }

  private func validateRecordingPermissions() throws {
    refreshPermissions()
    guard permissionState(for: .microphone)?.isReady == true else {
      throw NSError(
        domain: "Vhrase.Permissions",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Grant Microphone access in System before recording."]
      )
    }
  }

  private func beginStopAndProcess() {
    guard isRecording,
      let id = recordingID,
      let recorder
    else {
      return
    }
    status = .transcribing
    Task {
      await stopAndProcess(
        id: id,
        recorder: recorder
      )
    }
  }

  private func stopAndProcess(
    id: UUID,
    recorder: AudioRecorder
  ) async {
    let processingStarted = ContinuousClock.now
    let session = realtimeSession
    let configuration = recordingConfiguration ?? currentRecordingConfiguration()
    do {
      try ensureCurrentRecording(id)
      let fileURL = try await recorder.stop()
      logger.notice("PCM capture ended; waiting for transcription")
      processingAudioURL = fileURL
      defer {
        try? FileManager.default.removeItem(at: fileURL)
        if processingAudioURL == fileURL {
          processingAudioURL = nil
        }
      }
      stopRecordingTimer()
      self.recorder = nil
      realtimeSession = nil
      guard recordingSpeechPresence?.hasLikelySpeech == true else {
        throw RecordingContentError.noSpeechDetected
      }
      let started = Date()
      let result: TranscriptionResult
      if let session {
        result = try await session.finish()
      } else {
        result = try await transcriptionClient(configuration: configuration)
          .transcribe(fileURL: fileURL, settings: configuration.settings)
      }

      let transcriptionSeconds = Date().timeIntervalSince(started)
      try await finalizeTranscript(
        result,
        adjustment: .provider,
        configuration: configuration
      )
      lastTranscriptionSeconds = transcriptionSeconds
      let elapsed = processingStarted.duration(to: .now).components
      activityDays = activityStore.record(
        text: lastTranscript, recordingSeconds: recorder.recordedSeconds,
        processingSeconds: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18,
        settings: configuration.settings, days: activityDays)
    } catch {
      let failure = error as NSError
      logger.error(
        "Processing failed domain=\(failure.domain, privacy: .public) code=\(failure.code)")
      session?.cancel()
      recorder.cancel()
      guard recordingID == id else {
        return
      }
      realtimeSession = nil
      self.recorder = nil
      stopRecordingTimer()
      clearRecordingContext()
      status = .failed(error.localizedDescription)
    }
  }

  private func transcriptionClient(
    configuration: RecordingConfiguration
  ) -> SpeechToTextClient {
    switch configuration.settings.provider {
    case .xai:
      XAITranscriptionClient(apiKey: configuration.providerAPIKey)
    case .elevenLabs:
      ElevenLabsTranscriptionClient(apiKey: configuration.providerAPIKey)
    case .gemini:
      GeminiTranscriptionClient(apiKey: configuration.providerAPIKey)
    }
  }

  private func startRealtimeSessionIfNeeded(
    configuration: RecordingConfiguration,
    recordingID: UUID
  ) throws -> RealtimeTranscriptionSession? {
    let settings = configuration.settings
    guard settings.transcriptionMode == .realtime else {
      return nil
    }

    switch settings.provider {
    case .gemini:
      throw NSError(
        domain: "Vhrase.STT", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Choose Upload for Gemini transcription."])
    case .xai:
      return try XAIRealtimeTranscriptionClient(apiKey: configuration.providerAPIKey).start(
        settings: settings,
        onPartialTranscript: partialTranscriptHandler(recordingID: recordingID)
      )
    case .elevenLabs:
      return try ElevenLabsRealtimeTranscriptionClient(apiKey: configuration.providerAPIKey).start(
        settings: settings,
        onPartialTranscript: partialTranscriptHandler(recordingID: recordingID)
      )
    }
  }

  private func runDemoDictationPipeline() async {
    lastTranscriptionSeconds = nil
    let configuration = currentRecordingConfiguration()
    recordingTargetApp = appContext.targetApp()
    targetAppLabel = recordingTargetApp?.name ?? ""
    do {
      try await pauseForDemoVisibility()
      let result = TranscriptionResult(
        text: "Please send this custom dictation demo to open AI and x AI using eleven labs.",
        providerName: "Local Demo",
        duration: nil
      )
      try await finalizeTranscript(
        result,
        adjustment: .localDemo,
        configuration: configuration.withCopyOnlyDelivery()
      )
    } catch {
      clearRecordingContext()
      status = .failed(error.localizedDescription)
    }
  }

  private func validateSelectedProvider(
    _ configuration: RecordingConfiguration
  ) throws {
    try TranscriptionContract.validate(settings: configuration.settings)
    guard configuration.providerAPIKey.isEmpty else {
      return
    }
    throw missingProviderKey(secretKey(for: configuration.settings.provider).rawValue)
  }

  private func permissionState(for permission: AppPermission) -> PermissionState? {
    permissions.first { $0.permission == permission }?.state
  }

  private func missingProviderKey(_ name: String) -> NSError {
    NSError(
      domain: "Vhrase.Settings",
      code: 1,
      userInfo: [
        NSLocalizedDescriptionKey: "\(name) is missing. Add it in System before recording."
      ]
    )
  }

  private func currentRecordingConfiguration() -> RecordingConfiguration {
    var resolvedSettings = settings
    resolvedSettings.adjustmentBaseURL = effectiveLLMBaseURL
    return RecordingConfiguration(
      settings: resolvedSettings,
      providerAPIKey: effectiveAPIKey(secretKey(for: settings.provider)),
      llmAPIKey: effectiveLLMAPIKey
    )
  }

  private func effectiveAPIKey(_ key: SecretKey) -> String {
    apiKeys.effectiveValue(
      for: key,
      savedValue: self[keyPath: apiKeyPath(for: key)]
    )
  }

  private func secretKey(for provider: STTProvider) -> SecretKey {
    switch provider {
    case .xai: .xaiAPIKey
    case .elevenLabs: .elevenLabsAPIKey
    case .gemini: .geminiAPIKey
    }
  }

  /// Uses the same editable credential field for launch reads, user edits, and persistence retries.
  private func apiKeyPath(for key: SecretKey) -> ReferenceWritableKeyPath<AppState, String> {
    switch key {
    case .xaiAPIKey: \.xaiAPIKey
    case .elevenLabsAPIKey: \.elevenLabsAPIKey
    case .geminiAPIKey: \.geminiAPIKey
    case .llmAPIKey: \.llmAPIKey
    }
  }

  /// Completes the pending Keychain batch and clears its debounce state.
  private func savePendingAPIKeys() {
    apiKeySaveTask = nil
    let keys = pendingAPIKeySaves
    pendingAPIKeySaves.removeAll()
    saveAPIKeys(keys)
  }

  /// Persists changed preferences and refreshes global listeners only when their key definition changed.
  private func persistSettings(previous: DictationSettings) {
    settingsStore.save(settings)
    if settings.hotkeyPreset != previous.hotkeyPreset
      || settings.customHotkey != previous.customHotkey
    {
      registerHotkey()
    }
  }

  /// Rejects stale continuations before they can mutate resources owned by a newer recording.
  private func ensureCurrentRecording(_ id: UUID) throws {
    try Task.checkCancellation()
    guard recordingID == id else {
      throw CancellationError()
    }
  }

  /// Cleans up a startup failure only when this task still owns the active recording generation.
  private func finishRecordingStartup(
    id: UUID,
    error: Error?
  ) {
    guard recordingID == id else {
      return
    }
    realtimeSession = nil
    recorder = nil
    recordingTask = nil
    stopRecordingTimer()
    clearRecordingContext()
    if let error {
      status = .failed(error.localizedDescription)
    } else if status == .preparing {
      status = .idle
    }
  }

  private func registerHotkey() {
    hotkeyManager.register(
      settings,
      onPressed: { [weak self] in
        self?.handleHotkeyPressed()
      },
      onReleased: { [weak self] in
        self?.handleHotkeyReleased()
      }
    )
    fnHotkeyManager.register(
      settings,
      onPressed: { [weak self] in
        self?.handleHotkeyPressed()
      },
      onReleased: { [weak self] in
        self?.handleHotkeyReleased()
      }
    )
  }

  private func shouldIgnoreDuplicateHotkeyPress() -> Bool {
    let now = Date()
    defer {
      lastHotkeyPressDate = now
    }

    guard let lastHotkeyPressDate else {
      return false
    }

    return now.timeIntervalSince(lastHotkeyPressDate) < 0.2
  }

  private func performShortcutAction(_ action: ShortcutAction) {
    switch action {
    case .toggleRecording:
      toggleRecording()
    case .beginRecording:
      beginRecording()
    case .finishRecording:
      beginStopAndProcess()
    case .cancelRecording:
      cancelRecording()
    case .none:
      break
    }
  }

  /// Prevents late provider callbacks from mutating a newer recording generation.
  private func partialTranscriptHandler(
    recordingID: UUID
  ) -> @Sendable (String) -> Void {
    { [weak self] text in
      Task { @MainActor in
        guard self?.recordingID == recordingID else {
          return
        }
        self?.liveTranscript = text
      }
    }
  }

  private func resetLiveRecordingState() {
    liveTranscript = ""
    recordingLevel = 0
    recordingElapsedSeconds = 0
    lastDelivery = .none
    lastAdjustmentWarning = ""
  }

  private func startRecordingTimer() {
    recordingTimer?.invalidate()
    let startedAt = Date()
    recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self else {
          return
        }
        let elapsedSeconds = Int(Date().timeIntervalSince(startedAt))
        guard elapsedSeconds != self.recordingElapsedSeconds else {
          return
        }
        self.recordingElapsedSeconds = elapsedSeconds
      }
    }
  }

  private func stopRecordingTimer() {
    recordingTimer?.invalidate()
    recordingTimer = nil
    recordingLevel = 0
  }

  private func finalizeTranscript(
    _ result: TranscriptionResult,
    adjustment: AdjustmentExecution,
    configuration: RecordingConfiguration
  ) async throws {
    let settings = configuration.settings
    let targetApp = recordingTargetApp ?? appContext.targetApp()
    if settings.adjustWithLLM {
      status = .adjusting
      if adjustment == .localDemo {
        try await pauseForDemoVisibility()
      }
    }
    let finalized = try await TranscriptFinalizer(
      settings: settings,
      llmAPIKey: configuration.llmAPIKey
    )
    .finalize(
      result,
      adjustment: adjustment,
      targetApp: targetApp
    )

    lastRecognizedTranscript = result.text
    lastTranscript = finalized.text
    liveTranscript = ""
    recordHistory(
      text: finalized.text,
      providerName: result.providerName,
      transcriptionMode: settings.transcriptionMode.title,
      targetApp: finalized.targetApp,
      cleanup: finalized.cleanup
    )
    var warnings = [finalized.warning].filter { !$0.isEmpty }
    var delivery: TranscriptDelivery?
    var copyFallbackReason: String?

    switch configuration.deliveryPlan {
    case .copyOnly:
      break
    case .insert(let keepOnClipboard):
      refreshPermissions()
      if permissionState(for: .accessibility)?.isReady != true {
        copyFallbackReason =
          "Copied the transcript because Accessibility permission is unavailable."
      } else if let targetApp,
        await appContext.activate(targetApp)
      {
        do {
          let clipboardRetained = try await inserter.paste(
            finalized.text,
            keepOnClipboard: keepOnClipboard
          )
          delivery = .pasteCommandSent(
            clipboardRetained: clipboardRetained
          )
        } catch {
          copyFallbackReason = error.localizedDescription
        }
      } else {
        copyFallbackReason = "Copied the transcript because the target app was unavailable."
      }
    }

    if delivery == nil {
      if let copyFallbackReason {
        warnings.append(copyFallbackReason)
      }
      do {
        try inserter.copy(finalized.text)
        delivery = .copied
      } catch {
        warnings.append(error.localizedDescription)
      }
    }
    lastDelivery = delivery ?? .none
    lastAdjustmentWarning = warnings.joined(separator: " ")
    clearRecordingContext()
    status = .completed
  }

  private func pauseForDemoVisibility() async throws {
    try await Task.sleep(nanoseconds: 650_000_000)
  }

  private func recordHistory(
    text: String,
    providerName: String,
    transcriptionMode: String,
    targetApp: FrontmostApp?,
    cleanup: TranscriptCleanup
  ) {
    guard !text.isEmpty else {
      return
    }

    let item = TranscriptHistoryItem(
      id: UUID(),
      createdAt: Date(),
      text: text,
      provider: providerName,
      transcriptionMode: transcriptionMode,
      cleanup: cleanup,
      targetAppName: targetApp?.name,
      targetAppBundleIdentifier: targetApp?.bundleIdentifier
    )
    history = historyStore.prepend(item, to: history)
  }

  private func clearRecordingContext() {
    recordingID = nil
    recordingConfiguration = nil
    recordingSpeechPresence = nil
    recordingTargetApp = nil
    targetAppLabel = ""
  }

  /// Combines content-free daily totals without consulting the separately retained transcript archive.
  func todayActivity(now: Date = Date()) -> DictationActivityDay {
    activityDays.reduce(into: DictationActivityDay(date: now)) { total, day in
      if Calendar.current.isDate(day.date, inSameDayAs: now) {
        total.add(day)
      }
    }
  }
}

private struct RecordingConfiguration {
  let settings: DictationSettings
  let providerAPIKey: String
  let llmAPIKey: String
  private(set) var deliveryPlan: DeliveryPlan

  init(
    settings: DictationSettings,
    providerAPIKey: String,
    llmAPIKey: String
  ) {
    self.settings = settings
    self.providerAPIKey = providerAPIKey
    self.llmAPIKey = llmAPIKey
    deliveryPlan = .insert(
      keepOnClipboard: settings.keepTranscriptOnClipboard
    )
  }

  func withCopyOnlyDelivery() -> RecordingConfiguration {
    var copy = self
    copy.deliveryPlan = .copyOnly
    return copy
  }
}

private enum DeliveryPlan {
  case insert(keepOnClipboard: Bool)
  case copyOnly
}

/// Accepts very quiet speech while rejecting recordings that never rise above the existing live-waveform noise floor.
private final class SpeechPresenceGate: @unchecked Sendable {
  private static let minimumLevel = 0.012
  private static let requiredChunks = 2

  private let lock = NSLock()
  private var audibleChunkCount = 0

  func observe(level: Double) {
    guard level > Self.minimumLevel else { return }
    lock.withLock {
      audibleChunkCount += 1
    }
  }

  var hasLikelySpeech: Bool {
    lock.withLock {
      audibleChunkCount >= Self.requiredChunks
    }
  }
}

private enum RecordingContentError: LocalizedError {
  case noSpeechDetected

  var errorDescription: String? {
    "No speech was detected."
  }
}
