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
  /// Enough level samples for Dictate's full-width signal line; smaller surfaces read their own suffix.
  private static let recordingWaveformHistoryLimit = 96
  private static let workflowOutcomeDisplayDuration = Duration.seconds(4)

  @Published private(set) var status: AppStatus = .idle {
    didSet {
      guard status != oldValue else { return }
      scheduleWorkflowOutcomeDismissal(for: status)
      updateEscapeKeyMonitoring()
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
  @Published private(set) var settings: DictationSettings
  /// Editable credential values: saved secrets, this session's edits, or the LLM environment reference, never environment fallbacks.
  @Published private var apiKeyFields: [SecretKey: String] = [:]
  @Published private(set) var unsavedAPIKeys: Set<SecretKey> = []
  @Published private(set) var keychainReadNotice = ""
  @Published private(set) var lastTranscript = ""
  @Published private(set) var lastRecognizedTranscript = ""
  @Published private(set) var lastTranscriptionSeconds: Double?
  @Published private(set) var liveTranscript = ""
  @Published private(set) var recordingLevel = 0.0
  @Published private(set) var recordingWaveformHistory: [Double] = []
  let audioInputPreview = AudioInputPreview()
  @Published private(set) var recordingElapsedSeconds = 0
  @Published private(set) var permissions: [PermissionSnapshot] = []
  @Published private(set) var history: [TranscriptHistoryItem] = [] {
    didSet {
      cachedHistoryIndex = nil
    }
  }
  @Published private(set) var activityDays: [DictationActivityDay] = []
  @Published private(set) var savesTranscriptHistory = true
  @Published private(set) var lastAdjustmentWarning = ""
  @Published private(set) var lastCompletion: WorkflowCompletion = .transcript(.none)
  @Published private(set) var targetAppLabel = ""
  @Published private(set) var customizationNotice = ""
  @Published private(set) var openCCInstallationState = OpenCCInstallationState.idle
  @Published private(set) var isCheckingLLMModelAccess = false
  @Published private(set) var isWorkflowPopupDismissed = false {
    didSet {
      updateEscapeKeyMonitoring()
    }
  }

  /// Reuses normalized transcripts across History renders and searches until the saved history changes.
  var historyIndex: HistorySearch.Index {
    if let cachedHistoryIndex {
      return cachedHistoryIndex
    }
    let index = HistorySearch.Index(history)
    cachedHistoryIndex = index
    return index
  }

  private let settingsStore = SettingsStore()
  private let historyStore = TranscriptHistoryStore()
  private let activityStore = DictationActivityStore()
  private let apiKeys: APIKeyStore
  private let customizationTransfer = CustomizationTransfer()
  private let inserter = TextInsertion()
  private let focusedTextService = FocusedTextService()
  private let permissionManager = PermissionManager()
  private let appContext = AppContext()
  private let openCCInstaller = OpenCCInstaller()
  private let hotkeyManager = GlobalHotkeyManager()
  private let fnHotkeyManager = FnHotkeyManager()
  private let escapeKeyMonitor = EscapeKeyMonitor()
  private var recorder: AudioRecorder?
  private let logger = Logger(subsystem: "local.codex.Vhrase", category: "Dictation")
  private var recordingSequence = 0
  private var recordingWaveformTick = 0
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
  private var shortcutGesture = ShortcutGestureInterpreter()
  private var textPolishTask: Task<Void, Never>?
  private var textPolishID: UUID?
  private var activeWorkflow = ActiveWorkflow.dictation
  private var apiKeySaveTask: Task<Void, Never>?
  private var pendingAPIKeySaves: Set<SecretKey> = []
  private var editedAPIKeys: Set<SecretKey> = []
  private var shouldLoadSavedAPIKeysAfterLaunch = false
  private var cachedHistoryIndex: HistorySearch.Index?
  private let ownsInstance: Bool

  init(ownsInstance: Bool) {
    self.ownsInstance = ownsInstance
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
    apiKeyFields = [.llmAPIKey: apiKeys.savedLLMCredentialReference()]
    shouldLoadSavedAPIKeysAfterLaunch = developmentEnvironmentFileURL == nil
    history = historyStore.load()
    activityDays = activityStore.load()
    savesTranscriptHistory = historyStore.savesHistory
    lastTranscript = history.first?.text ?? ""
    if ownsInstance {
      AudioRecorder.removeAbandonedRecordings()
    }
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
    let keys = SecretKey.allCases.filter { key in
      !editedAPIKeys.contains(key)
        && !(key == .llmAPIKey
          && APIKeyStore.isCredentialEnvironmentVariableName(apiKeyField(.llmAPIKey)))
    }
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
        apiKeyFields[key] = value
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

  /// Returns the credential field shown for editing, which excludes environment fallbacks.
  func apiKeyField(_ key: SecretKey) -> String {
    apiKeyFields[key, default: ""]
  }

  /// Resolves the credential a request will use: the edited or saved field first, then its environment fallback.
  func effectiveAPIKey(_ key: SecretKey) -> String {
    apiKeys.effectiveValue(for: key, savedValue: apiKeyField(key))
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
      selectedProviderHasKey: !selectedProviderAPIKey.isEmpty,
      permissions: permissions,
      liveTranscript: liveTranscript,
      recordingElapsedSeconds: recordingElapsedSeconds,
      completion: lastCompletion
    )
  }

  func usesEnvironmentFallback(for key: SecretKey) -> Bool {
    apiKeys.usesEnvironmentFallback(for: key, savedValue: apiKeyField(key))
  }

  var isRecording: Bool {
    status == .recording
  }

  var isTextPolishing: Bool {
    textPolishID != nil
  }

  /// Lists setup work in priority order, or a single Ready diagnostic when nothing needs attention.
  var setupDiagnostics: [SetupDiagnostic] {
    SetupDiagnostics(
      settings: settings,
      selectedProviderHasKey: !selectedProviderAPIKey.isEmpty,
      hasLLMKey: !effectiveAPIKey(.llmAPIKey).isEmpty,
      permissions: permissions,
      chineseConversionIsAvailable: ChineseTextConverter.isAvailable
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

  /// Repeats the workflow that most recently failed without changing the configured shortcut gesture.
  func retryLastWorkflow() {
    switch activeWorkflow {
    case .dictation:
      toggleRecording()
    case .textPolish:
      beginTextPolish()
    }
  }

  /// Cancels microphone startup or active capture without sending audio to a provider.
  func cancelRecording() {
    guard status == .preparing || status == .recording else {
      return
    }

    releaseRecording()
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

  /// Cancels the active transient workflow when possible and otherwise hides its non-blocking feedback immediately.
  @discardableResult
  func handleEscapeCommand() -> Bool {
    switch status {
    case .preparing, .recording:
      cancelRecording()
      return true
    case .adjusting where isTextPolishing:
      cancelTextPolish()
      return true
    case .transcribing, .adjusting:
      guard !isWorkflowPopupDismissed else { return false }
      isWorkflowPopupDismissed = true
      return true
    case .completed, .failed:
      dismissWorkflowOutcome()
      return true
    case .idle:
      guard !customizationNotice.isEmpty else {
        return false
      }
      customizationNotice = ""
      return true
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
    guard !isShortcutCaptureActive else {
      logger.notice("Shortcut press ignored during capture")
      return
    }

    customizationNotice = "Shortcut \(settings.hotkeyDisplay) pressed."
    let action = shortcutGesture.press(
      at: ProcessInfo.processInfo.systemUptime,
      status: status
    )
    logger.notice("Shortcut pressed action=\(String(describing: action), privacy: .public)")
    performShortcutAction(action)
  }

  func handleHotkeyReleased() {
    logger.notice("Shortcut released")
    performShortcutAction(
      shortcutGesture.release(
        at: ProcessInfo.processInfo.systemUptime,
        status: status
      )
    )
  }

  /// Saves only explicitly edited credentials so an unrelated field cannot erase an unread Keychain item.
  private func saveAPIKeys(_ keys: Set<SecretKey>) {
    guard !keys.isEmpty else {
      return
    }
    var failures: [String] = []
    for key in keys {
      let value = apiKeyField(key)
      if key == .llmAPIKey,
        APIKeyStore.isCredentialEnvironmentVariableName(value)
      {
        apiKeys.saveLLMCredentialReference(value)
        unsavedAPIKeys.remove(key)
        continue
      }
      if key == .llmAPIKey {
        apiKeys.saveLLMCredentialReference("")
      }
      do {
        try apiKeys.save(value, for: key)
        unsavedAPIKeys.remove(key)
      } catch {
        unsavedAPIKeys.insert(key)
        failures.append(error.localizedDescription)
      }
    }
    customizationNotice =
      failures.isEmpty
      ? "Credential changes saved. Secrets use macOS Keychain; environment references use local preferences."
      : failures.joined(separator: " ") + " Unsaved changes apply only for this session."
  }

  /// Retries explicit credential edits without opening a system authentication dialog.
  func retrySavingAPIKeys() {
    saveAPIKeys(unsavedAPIKeys)
  }

  /// Updates one editable credential and debounces its Keychain write for 500 milliseconds.
  func updateAPIKey(_ key: SecretKey, value: String) {
    guard value != apiKeyField(key) else {
      return
    }

    apiKeyFields[key] = value

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

  /// Opens the privacy pane for granted access; otherwise requests it, falling back to the pane where macOS requires it.
  func handlePermissionAction(_ permission: AppPermission) {
    guard permissionState(for: permission)?.isReady != true else {
      permissionManager.openSettings(for: permission)
      return
    }
    Task {
      await permissionManager.request(permission)
      refreshPermissions()
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
    if lastCompletion.isTranscript {
      lastCompletion = .transcript(.none)
    }
    lastAdjustmentWarning = ""
    if status == .completed, lastCompletion.isTranscript {
      status = .idle
    }
  }

  /// Releases active capture resources and removes any recording owned by an in-flight transcription before app exit.
  func prepareForTermination() {
    guard ownsInstance else { return }
    escapeKeyMonitor.setEnabled(false, onEscape: {})
    workflowOutcomeDismissTask?.cancel()
    workflowOutcomeDismissTask = nil
    audioInputPreview.stop()
    flushPendingAPIKeySave()
    textPolishID = nil
    textPolishTask?.cancel()
    textPolishTask = nil
    releaseRecording()
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

    activeWorkflow = .dictation
    status = .transcribing
    isWorkflowPopupDismissed = false
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
    let apiKey = effectiveAPIKey(.llmAPIKey)
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
        try await LLMAdjustmentClient(
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

    activeWorkflow = .dictation
    isWorkflowPopupDismissed = false
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
          self.recordingWaveformTick += 1
          if self.recordingWaveformTick >= 3 {
            self.recordingWaveformTick = 0
            self.recordingWaveformHistory.append(chunk.level)
            let limit = Self.recordingWaveformHistoryLimit
            if self.recordingWaveformHistory.count > limit {
              self.recordingWaveformHistory.removeFirst(
                self.recordingWaveformHistory.count - limit
              )
            }
          }
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
      let transcriptionStarted = ContinuousClock.now
      let result: TranscriptionResult
      if let session {
        result = try await session.finish()
      } else {
        result = try await transcriptionClient(configuration: configuration)
          .transcribe(fileURL: fileURL, settings: configuration.settings)
      }

      try await finalizeTranscript(
        result,
        adjustment: .provider,
        configuration: configuration,
        timing: DictationTiming(
          recordingSeconds: recorder.recordedSeconds,
          transcriptionSeconds: transcriptionStarted.duration(to: .now) / .seconds(1),
          processingStarted: processingStarted
        )
      )
    } catch {
      let failure = error as NSError
      logger.error(
        "Processing failed domain=\(failure.domain, privacy: .public) code=\(failure.code)")
      session?.cancel()
      recorder.cancel()
      guard recordingID == id else {
        return
      }
      releaseRecording()
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
    guard configuration.settings.transcriptionMode == .realtime else {
      return nil
    }
    return try RealtimeTranscriptionSession.start(
      settings: configuration.settings,
      apiKey: configuration.providerAPIKey,
      onPartialTranscript: partialTranscriptHandler(recordingID: recordingID)
    )
  }

  private func runDemoDictationPipeline() async {
    let configuration = currentRecordingConfiguration()
    recordingTargetApp = appContext.targetApp()
    targetAppLabel = recordingTargetApp?.name ?? ""
    do {
      try await pauseForDemoVisibility()
      let result = TranscriptionResult(
        text: "Please send this custom dictation demo to open AI and x AI using eleven labs.",
        providerName: "Local Demo"
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
    throw missingProviderKey(SecretKey(configuration.settings.provider).rawValue)
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
      providerAPIKey: selectedProviderAPIKey,
      llmAPIKey: effectiveAPIKey(.llmAPIKey)
    )
  }

  private var selectedProviderAPIKey: String {
    effectiveAPIKey(SecretKey(settings.provider))
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
    releaseRecording()
    if let error {
      status = .failed(error.localizedDescription)
    } else if status == .preparing {
      status = .idle
    }
  }

  /// Stops every resource owned by the active recording, then clears its live feedback and target context.
  private func releaseRecording() {
    recordingTask?.cancel()
    recordingTask = nil
    realtimeSession?.cancel()
    realtimeSession = nil
    recorder?.cancel()
    recorder = nil
    stopRecordingTimer()
    clearRecordingContext()
  }

  private func registerHotkey() {
    guard ownsInstance else {
      return
    }
    shortcutGesture.reset()
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

  private func updateEscapeKeyMonitoring() {
    guard ownsInstance else {
      return
    }
    escapeKeyMonitor.setEnabled(
      status.showsWorkflowPopup && !isWorkflowPopupDismissed,
      onEscape: { [weak self] in
        self?.handleEscapeCommand()
      }
    )
  }

  private func performShortcutAction(_ action: ShortcutAction) {
    switch action {
    case .beginRecording:
      beginRecording()
    case .finishRecording:
      beginStopAndProcess()
    case .cancelRecording:
      cancelRecording()
    case .cancelRecordingAndPolishText:
      cancelRecording()
      dismissWorkflowOutcome()
      beginTextPolish()
    case .none:
      break
    }
  }

  /// Captures the focused editor before contacting the LLM and replaces it only if the same source remains focused when the result returns.
  private func beginTextPolish() {
    guard status.canStartRecording else {
      return
    }

    activeWorkflow = .textPolish
    isWorkflowPopupDismissed = false
    audioInputPreview.stop()
    let target: FocusedTextTarget
    let client: LLMAdjustmentClient
    let polishSettings = settings
    let model = polishSettings.adjustmentModel.trimmingCharacters(in: .whitespacesAndNewlines)
    do {
      target = try focusedTextService.capture()
      guard !model.isEmpty else {
        throw TextPolishError.missingModel
      }
      client = LLMAdjustmentClient(
        apiKey: effectiveAPIKey(.llmAPIKey),
        baseURL: effectiveLLMBaseURL
      )
      try client.validateConfiguration()
    } catch {
      status = .failed(error.localizedDescription)
      return
    }

    let id = UUID()
    let includeScreenshot = settings.includeScreenshot
    textPolishID = id
    status = .adjusting
    customizationNotice = "Polishing text in \(target.app.name)…"
    textPolishTask = Task { [weak self] in
      guard let self else { return }
      let screenshotDataURL: String? =
        if includeScreenshot { await ScreenContext().mainDisplayPNGDataURL() } else { nil }
      do {
        let replacement = try await client.polish(
          text: target.text,
          screenshotDataURL: screenshotDataURL,
          settings: polishSettings,
          app: target.app
        )
        try Task.checkCancellation()
        guard self.textPolishID == id else {
          return
        }
        guard await self.appContext.activate(target.app) else {
          throw TextPolishError.targetUnavailable
        }
        // Activation yields to Escape handling; a cancelled rewrite must not alter the editor's selection.
        try Task.checkCancellation()
        try target.prepareReplacement()
        _ = try await self.inserter.paste(replacement, keepOnClipboard: false)
        guard self.textPolishID == id else {
          return
        }
        self.textPolishTask = nil
        self.textPolishID = nil
        self.lastCompletion = .textPolished
        self.customizationNotice = "Polished the focused text in \(target.app.name)."
        self.status = .completed
      } catch is CancellationError {
        guard self.textPolishID == id else { return }
        self.textPolishTask = nil
        self.textPolishID = nil
        self.status = .idle
      } catch {
        guard self.textPolishID == id else { return }
        self.textPolishTask = nil
        self.textPolishID = nil
        self.status = .failed(error.localizedDescription)
      }
    }
  }

  /// Cancels an in-flight text rewrite without modifying the focused editor.
  func cancelTextPolish() {
    guard textPolishID != nil else {
      return
    }
    textPolishID = nil
    textPolishTask?.cancel()
    textPolishTask = nil
    status = .idle
    customizationNotice = "Text polishing cancelled."
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
    recordingWaveformHistory = []
    recordingWaveformTick = 0
    recordingElapsedSeconds = 0
    lastCompletion = .transcript(.none)
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
    recordingWaveformHistory = []
    recordingWaveformTick = 0
  }

  /// Publishes finalized text, returns it to the target app, and records history and activity with one processing measurement.
  private func finalizeTranscript(
    _ result: TranscriptionResult,
    adjustment: AdjustmentExecution,
    configuration: RecordingConfiguration,
    timing: DictationTiming? = nil
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
    let (delivery, deliveryWarnings) = await deliver(
      finalized.text,
      plan: configuration.deliveryPlan,
      to: targetApp
    )
    lastCompletion = .transcript(delivery)
    lastAdjustmentWarning = ([finalized.warning].filter { !$0.isEmpty } + deliveryWarnings)
      .joined(separator: " ")
    lastTranscriptionSeconds = timing?.transcriptionSeconds
    let processingSeconds = timing.map { $0.processingStarted.duration(to: .now) / .seconds(1) }
    history = historyStore.prepend(
      TranscriptHistoryItem(
        id: UUID(),
        createdAt: Date(),
        text: finalized.text,
        provider: result.providerName,
        transcriptionMode: settings.transcriptionMode.title,
        cleanup: finalized.cleanup,
        targetAppName: targetApp?.name,
        targetAppBundleIdentifier: targetApp?.bundleIdentifier,
        refinement: finalized.refinement,
        recordingSeconds: timing?.recordingSeconds,
        transcriptionSeconds: timing?.transcriptionSeconds,
        processingSeconds: processingSeconds
      ),
      to: history
    )
    if let timing, let processingSeconds {
      activityDays = activityStore.record(
        text: finalized.text,
        recordingSeconds: timing.recordingSeconds,
        processingSeconds: processingSeconds,
        settings: settings,
        days: activityDays
      )
    }
    clearRecordingContext()
    status = .completed
  }

  /// Pastes into the recorded target when possible; otherwise leaves the text on the clipboard and explains why.
  private func deliver(
    _ text: String,
    plan: DeliveryPlan,
    to targetApp: FrontmostApp?
  ) async -> (delivery: TranscriptDelivery, warnings: [String]) {
    var warnings: [String] = []
    if case .insert(let keepOnClipboard) = plan {
      refreshPermissions()
      if permissionState(for: .accessibility)?.isReady != true {
        warnings.append("Copied the transcript because Accessibility permission is unavailable.")
      } else if let targetApp, await appContext.activate(targetApp) {
        do {
          let clipboardRetained = try await inserter.paste(
            text,
            keepOnClipboard: keepOnClipboard,
            context: focusedTextService.insertionContext()
          )
          return (.pasteCommandSent(clipboardRetained: clipboardRetained), [])
        } catch {
          warnings.append(error.localizedDescription)
        }
      } else {
        warnings.append("Copied the transcript because the target app was unavailable.")
      }
    }
    do {
      try inserter.copy(text)
      return (.copied, warnings)
    } catch {
      warnings.append(error.localizedDescription)
      return (.none, warnings)
    }
  }

  private func pauseForDemoVisibility() async throws {
    try await Task.sleep(for: .milliseconds(650))
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

/// Measurements recorded for a real dictation; demos have none.
private struct DictationTiming {
  let recordingSeconds: Double
  let transcriptionSeconds: Double
  let processingStarted: ContinuousClock.Instant
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

private enum ActiveWorkflow {
  case dictation
  case textPolish
}

private enum TextPolishError: LocalizedError {
  case missingModel
  case targetUnavailable

  var errorDescription: String? {
    switch self {
    case .missingModel:
      "Choose an LLM model before polishing text."
    case .targetUnavailable:
      "The app containing the text is no longer available. Nothing was replaced."
    }
  }
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
