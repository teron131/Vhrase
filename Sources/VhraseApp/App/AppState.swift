// Owns Vhrase's observable state and runs its workflows: dictation from shortcut press to delivered and saved transcript, double-tap polishing of the focused text, the setup recording test, and the settings, history, and permission actions the main window and menu bar call.

import Combine
import Foundation
import OSLog

@MainActor
final class AppState: ObservableObject {
  private static let workflowOutcomeDisplayDuration = Duration.seconds(4)

  @Published private(set) var status: AppStatus = .idle {
    didSet {
      guard status != oldValue else { return }
      scheduleWorkflowOutcomeDismissal(for: status)
      updateEscapeKeyMonitoring()
      logger.notice(
        "Workflow attempt=\(self.recordingSequence) phase=\(self.status.phaseName, privacy: .public)"
      )
    }
  }
  @Published private(set) var settings: DictationSettings
  let credentials = Credentials()
  @Published private(set) var lastTranscript = ""
  @Published private(set) var lastRecognizedTranscript = ""
  @Published private(set) var lastTranscriptionSeconds: Double?
  @Published private(set) var liveTranscript = ""
  /// The active recording's level and elapsed time, published apart from this object so they never re-evaluate every view.
  let recordingMeter = RecordingMeter()
  let audioInputPreview = AudioInputPreview()
  let transcriptionTest = TranscriptionTest()
  let openCCSetup = OpenCCSetup()
  let localModels: LocalModels
  @Published private(set) var permissions: [PermissionSnapshot] = []
  @Published private(set) var history: [TranscriptHistoryItem] = [] {
    didSet {
      historyIndexIsCurrent = false
    }
  }
  @Published private(set) var activityDays: [DictationActivityDay] = []
  @Published private(set) var savesTranscriptHistory = true
  @Published private(set) var lastAdjustmentWarning = ""
  @Published private(set) var lastCompletion: WorkflowCompletion = .transcript(.none)
  @Published private(set) var targetAppLabel = ""
  @Published private(set) var notice = ""
  @Published private(set) var isCheckingLLMModelAccess = false
  @Published private(set) var isWorkflowPopupDismissed = false {
    didSet {
      updateEscapeKeyMonitoring()
    }
  }

  var historyIndex: HistorySearch.Index {
    if let cachedHistoryIndex, historyIndexIsCurrent {
      return cachedHistoryIndex
    }
    let index = HistorySearch.Index(history, reusing: cachedHistoryIndex)
    cachedHistoryIndex = index
    historyIndexIsCurrent = true
    return index
  }

  private let settingsStore = SettingsStore()
  private let historyStore = TranscriptHistoryStore()
  private let activityStore = DictationActivityStore()
  private let customizationTransfer = CustomizationTransfer()
  private let inserter = TextInsertion()
  private let focusedTextService = FocusedTextService()
  private let permissionManager = PermissionManager()
  private let appContext = AppContext()
  private let hotkeyManager = GlobalHotkeyManager()
  private let fnHotkeyManager = FnHotkeyManager()
  private let escapeKeyMonitor = EscapeKeyMonitor()
  /// The active dictation's capture and recognition; its identity tells late continuations whether they still own the workflow.
  private var recording: TranscriptionRecording?
  private var childStateObservations: [AnyCancellable] = []
  private let logger = Logger(subsystem: "local.codex.Vhrase", category: "Dictation")
  private var recordingSequence = 0
  private var recordingTask: Task<Void, Never>?
  private var processingTask: Task<Void, Never>?
  private var workflowOutcomeDismissTask: Task<Void, Never>?
  private var recordingTargetApp: FrontmostApp?
  private var recordingConfiguration: RecordingConfiguration?
  private var isShortcutCaptureActive = false
  private var shortcutGesture = ShortcutGestureInterpreter()
  private var textPolishTask: Task<Void, Never>?
  private var textPolishID: UUID?
  private var polishingOperation = PolishOperation.refine
  private var activeWorkflow = ActiveWorkflow.dictation
  private var cachedHistoryIndex: HistorySearch.Index?
  private var historyIndexIsCurrent = false
  private let llmPrices = LLMPriceList()
  private let ownsInstance: Bool

  init(ownsInstance: Bool) {
    self.ownsInstance = ownsInstance
    let settings = settingsStore.load()
    self.settings = settings
    localModels = LocalModels(settings: settings)
    history = historyStore.load()
    activityDays = activityStore.load()
    savesTranscriptHistory = historyStore.savesHistory
    lastTranscript = history.first?.text ?? ""
    if ownsInstance {
      AudioRecorder.removeAbandonedRecordings()
    }
    notice = credentials.environmentNotice
    credentials.onNotice = { [weak self] notice in
      self?.notice = notice
    }
    openCCSetup.onNotice = { [weak self] notice in
      self?.notice = notice
    }
    // Readiness and recording availability depend on child workflows, so their changes refresh AppState observers.
    childStateObservations = [
      credentials.objectWillChange,
      localModels.parakeet.objectWillChange,
      localModels.huggingFace.objectWillChange,
      transcriptionTest.objectWillChange,
      openCCSetup.objectWillChange,
    ].map { changes in
      changes.sink { [weak self] _ in
        self?.objectWillChange.send()
      }
    }
    refreshPermissions()
    registerHotkey()
    if ownsInstance {
      localModels.prepareSelected()
    }
  }

  var effectiveLLMBaseURL: String {
    credentials.effectiveLLMBaseURL(savedValue: settings.adjustmentBaseURL)
  }

  /// Dictation and setup recording share capture and recognition resources, so neither starts while the other is active.
  var canStartRecording: Bool {
    status.canStartRecording && !transcriptionTest.state.isActive
  }

  var presentation: DictationPresentation {
    DictationPresentation(
      status: status,
      settings: settings,
      providerReadiness: selectedProviderReadiness,
      permissions: permissions,
      liveTranscript: liveTranscript,
      completion: lastCompletion
    )
  }

  var isRecording: Bool {
    status == .recording
  }

  var isTextPolishing: Bool {
    textPolishID != nil
  }

  var polishingProgress: String {
    polishingOperation.progress
  }

  /// Only local recognition stops cleanly mid-request; a cloud provider has already received the audio.
  var canCancelTranscription: Bool {
    status == .transcribing && recordingConfiguration?.settings.provider.location == .local
  }

  /// Lists setup work in priority order, or a single Ready diagnostic when nothing needs attention.
  var setupDiagnostics: [SetupDiagnostic] {
    SetupDiagnostics(
      settings: settings,
      providerReadiness: selectedProviderReadiness,
      hasLLMKey: !credentials.effectiveValue(.llmAPIKey).isEmpty,
      permissions: permissions,
      chineseConversionIsAvailable: openCCSetup.isInstalled
    ).build()
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

  /// Runs the record button's current action; only the calling surface knows how to show the System page.
  func performRecordAction(_ action: RecordAction, openSetup: () -> Void) {
    switch action {
    case .toggleRecording:
      toggleRecording()
    case .cancelRecording:
      cancelRecording()
    case .openSetup:
      openSetup()
    case .disabled:
      break
    }
  }

  func retryLastWorkflow() {
    switch activeWorkflow {
    case .dictation:
      toggleRecording()
    case .textPolish:
      beginTextPolish()
    }
  }

  func cancelRecording() {
    guard status == .preparing || status == .recording else {
      return
    }

    releaseRecording()
    liveTranscript = ""
    status = .idle
    notice = "Recording cancelled."
  }

  /// Stops local recognition of a finished recording; its audio is discarded and nothing is delivered or saved.
  func cancelTranscription() {
    guard canCancelTranscription else {
      return
    }

    processingTask?.cancel()
    processingTask = nil
    releaseRecording()
    status = .idle
    notice = "Transcription cancelled."
  }

  /// Ignored while dictation, polishing, or the setup test is running; the outcome arrives as a notice.
  func removeLocalModel(_ store: LocalModelStore) {
    guard canStartRecording else {
      return
    }
    let title = store.model.title
    Task {
      do {
        try await store.remove()
        notice = "\(title) model removed. Download it again to transcribe on this Mac."
      } catch {
        notice = "Couldn't remove the \(title) model: \(error.localizedDescription)"
      }
    }
  }

  func dismissWorkflowOutcome() {
    switch status {
    case .completed, .failed:
      status = .idle
    case .idle, .preparing, .recording, .transcribing, .adjusting:
      break
    }
  }

  /// Returns `false` when there is nothing to cancel or hide, so the caller can let the key event through.
  @discardableResult
  func handleEscapeCommand() -> Bool {
    if transcriptionTest.state.isActive {
      transcriptionTest.cancel()
      return true
    }
    switch status {
    case .preparing, .recording:
      cancelRecording()
      return true
    case .adjusting where isTextPolishing:
      cancelTextPolish()
      return true
    case .transcribing where canCancelTranscription:
      cancelTranscription()
      return true
    case .transcribing, .adjusting:
      guard !isWorkflowPopupDismissed else { return false }
      isWorkflowPopupDismissed = true
      return true
    case .completed, .failed:
      dismissWorkflowOutcome()
      return true
    case .idle:
      guard !notice.isEmpty else {
        return false
      }
      notice = ""
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
    guard !isShortcutCaptureActive, !transcriptionTest.state.isActive else {
      logger.notice("Shortcut press ignored during capture")
      return
    }

    notice = "Shortcut \(settings.hotkeyDisplay) pressed."
    let action = shortcutGesture.press(
      at: ProcessInfo.processInfo.systemUptime,
      status: status,
      gestures: settings.shortcutGestures
    )
    logger.notice("Shortcut pressed action=\(String(describing: action), privacy: .public)")
    performShortcutAction(action)
  }

  func handleHotkeyReleased() {
    guard !transcriptionTest.state.isActive else { return }
    logger.notice("Shortcut released")
    performShortcutAction(
      shortcutGesture.release(
        at: ProcessInfo.processInfo.systemUptime,
        status: status,
        gestures: settings.shortcutGestures
      )
    )
  }

  /// Ignored while the setup test runs. A transcription mode the chosen provider lacks falls back to `.upload` with a notice.
  func updateSettings(_ update: (inout DictationSettings) -> Void) {
    guard !transcriptionTest.state.isActive else { return }
    let previousSettings = settings
    update(&settings)
    if !settings.provider.availableModes.contains(settings.transcriptionMode) {
      settings.transcriptionMode = .upload
      notice =
        "\(settings.provider.title) transcribes after you stop recording. Switched to \(settings.transcriptionModeTitle)."
    }
    guard settings != previousSettings else {
      return
    }
    persistSettings(previous: previousSettings)
  }

  func beginShortcutCapture() {
    isShortcutCaptureActive = true
    notice = "Listening for a shortcut. Press Esc to cancel."
  }

  func setCustomShortcut(_ hotkey: CustomHotkey) {
    isShortcutCaptureActive = false
    updateSettings { settings in
      settings.hotkeyPreset = .custom
      settings.customHotkey = hotkey
    }
    notice = "STT shortcut set to \(hotkey.display)."
  }

  func setFnShortcut() {
    isShortcutCaptureActive = false
    updateSettings { settings in
      settings.hotkeyPreset = .fn
      settings.customHotkey = nil
    }
    notice = "STT shortcut set to Fn/Globe."
  }

  func cancelShortcutCapture() {
    isShortcutCaptureActive = false
    notice = "Shortcut capture cancelled."
  }

  func rejectShortcutCapture(_ message: String) {
    notice = message
  }

  /// Clears a transient action message without dismissing a newer replacement.
  func dismissNotice(_ notice: String) {
    guard self.notice == notice else {
      return
    }
    self.notice = ""
  }

  func disableShortcut() {
    updateSettings { settings in
      settings.hotkeyPreset = .disabled
      settings.customHotkey = nil
    }
    notice = "STT shortcut disabled."
  }

  func refreshPermissions() {
    permissions = permissionManager.snapshots()
    fnHotkeyManager.refreshAuthorization()
  }

  /// Opens the privacy pane for granted access; otherwise requests it, falling back to the pane where macOS requires it.
  func handlePermissionAction(_ permission: AppPermission) {
    guard !permissions.isReady(permission) else {
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
      notice = "Transcript copied."
    } catch {
      notice = error.localizedDescription
    }
  }

  func copyLastTranscript() {
    guard !lastTranscript.isEmpty else {
      return
    }
    do {
      try inserter.copy(lastTranscript)
      notice = "Last transcript copied."
    } catch {
      notice = error.localizedDescription
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

  /// Also deletes the recording an in-flight transcription still owns.
  func prepareForTermination() {
    guard ownsInstance else { return }
    escapeKeyMonitor.setEnabled(false, onEscape: {})
    workflowOutcomeDismissTask?.cancel()
    workflowOutcomeDismissTask = nil
    audioInputPreview.stop()
    transcriptionTest.cancel()
    credentials.flushPendingSave()
    localModels.cancelDownloadsAndPreparation()
    processingTask?.cancel()
    processingTask = nil
    textPolishID = nil
    textPolishTask?.cancel()
    textPolishTask = nil
    releaseRecording()
    HuggingFaceRuntime.stopAll()
    AudioRecorder.removeAbandonedRecordings()
  }

  func runDemoDictation() {
    guard canStartRecording else {
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
        notice = "Customization exported."
      }
    } catch {
      notice = "Export failed: \(error.localizedDescription)"
    }
  }

  func importCustomization() {
    do {
      switch try customizationTransfer.importSettings(replacing: settings) {
      case .dismissed:
        break
      case .reviewCancelled:
        notice = "Customization import cancelled."
      case .imported(let importedSettings):
        let previousSettings = settings
        settings = importedSettings
        persistSettings(previous: previousSettings)
        notice = "Customization imported."
      }
    } catch {
      notice = "Import failed: \(error.localizedDescription)"
    }
  }

  func checkLLMModelAccess() {
    guard !isCheckingLLMModelAccess else {
      return
    }
    let apiKey = credentials.effectiveValue(.llmAPIKey)
    guard !apiKey.isEmpty else {
      notice = "Add LLM API key before checking model access."
      return
    }

    let model = settings.adjustmentModel.trimmingCharacters(in: .whitespacesAndNewlines)
    let baseURL = effectiveLLMBaseURL
    isCheckingLLMModelAccess = true
    notice = "Checking LLM model: \(model)…"
    Task {
      defer { isCheckingLLMModelAccess = false }
      do {
        try await LLMAdjustmentClient(
          apiKey: apiKey,
          baseURL: baseURL
        )
        .checkModel(model)
        notice = "LLM model ready: \(model)."
      } catch {
        notice = "LLM model check failed for \(model): \(error.localizedDescription)"
      }
    }
  }

  private func beginRecording() {
    guard canStartRecording else {
      return
    }

    activeWorkflow = .dictation
    isWorkflowPopupDismissed = false
    audioInputPreview.stop()
    recordingSequence += 1
    logger.notice(
      "Begin attempt=\(self.recordingSequence) provider=\(self.settings.provider.rawValue, privacy: .public) mode=\(self.settings.transcriptionMode.rawValue, privacy: .public)"
    )
    let configuration = currentRecordingConfiguration()
    let recording = transcriptionRecording(
      settings: configuration.settings, apiKey: configuration.providerAPIKey)
    self.recording = recording
    recordingConfiguration = configuration
    status = .preparing
    recordingTask = Task { [weak self] in
      await self?.startRecording(recording, configuration: configuration)
    }
  }

  private func startRecording(
    _ recording: TranscriptionRecording,
    configuration: RecordingConfiguration
  ) async {
    // A recording cancelled before its startup ran has nothing to prepare, and must not reset a newer one's live state.
    guard self.recording === recording else {
      return
    }
    recordingTargetApp = appContext.targetApp()
    targetAppLabel = recordingTargetApp?.name ?? ""
    if let recordingTargetApp {
      focusedTextService.exposeText(in: recordingTargetApp)
    }
    resetLiveRecordingState()
    do {
      try validateRecordingPermissions()
      try validateSelectedProvider(
        settings: configuration.settings, apiKey: configuration.providerAPIKey)
      // Loading overlaps the user's speech when the model was released while idle.
      localModels.prepareSelected()
      try await recording.start(
        onLevel: { [weak self, weak recording] level in
          Task { @MainActor in
            guard let self, let recording, self.recording === recording else { return }
            self.recordingMeter.record(level)
          }
        },
        onPartialTranscript: partialTranscriptHandler(for: recording),
        onFailure: { [weak self, weak recording] error in
          guard let self, let recording, self.recording === recording else { return }
          self.cancelRecording()
          self.status = .failed(error.localizedDescription)
        })
      try ensureCurrentRecording(recording)
      recordingTask = nil
      recordingMeter.startClock()
      status = .recording
    } catch is CancellationError {
      finishRecordingStartup(recording, error: nil)
    } catch {
      let failure = error as NSError
      logger.error("Startup failed domain=\(failure.domain, privacy: .public) code=\(failure.code)")
      finishRecordingStartup(recording, error: error)
    }
  }

  private func validateRecordingPermissions() throws {
    refreshPermissions()
    guard permissions.isReady(.microphone) else {
      throw NSError(
        domain: "Vhrase.Permissions",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Grant Microphone access in System before recording."]
      )
    }
  }

  private func beginStopAndProcess() {
    guard isRecording, let recording, let configuration = recordingConfiguration else {
      return
    }
    status = .transcribing
    processingTask = Task {
      await stopAndProcess(recording, configuration: configuration)
    }
  }

  private func stopAndProcess(
    _ recording: TranscriptionRecording,
    configuration: RecordingConfiguration
  ) async {
    let processingStarted = ContinuousClock.now
    do {
      try await recording.stop()
      logger.notice("PCM capture ended; waiting for transcription")
      // Cancelling while capture drains may already have started a newer recording that owns the meter.
      try ensureCurrentRecording(recording)
      recordingMeter.reset()
      let screenshot = startScreenshot(for: configuration)
      let transcriptionStarted = ContinuousClock.now
      let result = try await recording.transcribe()
      // A cancelled or superseded recording must not deliver or save a late transcript.
      try ensureCurrentRecording(recording)

      try await finalizeTranscript(
        result,
        adjustment: .provider,
        configuration: configuration,
        screenshot: screenshot,
        timing: DictationTiming(
          recordingSeconds: recording.recordedSeconds,
          transcriptionSeconds: transcriptionStarted.duration(to: .now) / .seconds(1),
          processingStarted: processingStarted
        )
      )
    } catch {
      let failure = error as NSError
      logger.error(
        "Processing failed domain=\(failure.domain, privacy: .public) code=\(failure.code)")
      guard self.recording === recording else {
        return
      }
      releaseRecording()
      status = .failed(error.localizedDescription)
    }
  }

  /// Captures the screenshot LLM polishing will attach while the provider transcribes, keeping it off the critical path; nothing is captured unless screen context is on and the polish request could be sent.
  private func startScreenshot(for configuration: RecordingConfiguration) -> Task<String?, Never>? {
    let settings = configuration.settings
    guard settings.afterTranscription.usesLLM, settings.includeScreenshot else { return nil }
    do {
      try LLMAdjustmentClient(apiKey: configuration.llmAPIKey, baseURL: settings.adjustmentBaseURL)
        .validateConfiguration(model: settings.adjustmentModel)
    } catch {
      // Polishing fails the same check and falls back without a screenshot.
      return nil
    }
    let app = recordingTargetApp ?? appContext.targetApp()
    return Task { await LLMAdjustmentClient.captureDisplay(app, settings.screenshotResolution) }
  }

  private func transcriptionRecording(
    settings: DictationSettings, apiKey: String
  ) -> TranscriptionRecording {
    let client: any SpeechToTextClient =
      switch settings.provider {
      case .xai: XAITranscriptionClient(apiKey: apiKey)
      case .elevenLabs: ElevenLabsTranscriptionClient(apiKey: apiKey)
      case .gemini: GeminiTranscriptionClient(apiKey: apiKey)
      case .openAI: OpenAITranscriptionClient(apiKey: apiKey)
      case .vercel: VercelTranscriptionClient(apiKey: apiKey)
      case .parakeet: localModels.parakeet.model.recognizer
      case .huggingFace: localModels.huggingFace.model.recognizer
      }
    return TranscriptionRecording(settings: settings, apiKey: apiKey, client: client)
  }

  /// Tests the selected recognition setup without applying adjustment or invoking dictation delivery and storage.
  func startTranscriptionTest() {
    guard canStartRecording else { return }
    var settings = settings
    settings.afterTranscription = .off
    let apiKey = selectedProviderAPIKey
    do {
      try validateRecordingPermissions()
      try validateSelectedProvider(settings: settings, apiKey: apiKey)
      audioInputPreview.stop()
      localModels.prepareSelected()
      transcriptionTest.start(transcriptionRecording(settings: settings, apiKey: apiKey))
    } catch {
      transcriptionTest.reportFailure(error)
    }
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

  private func validateSelectedProvider(settings: DictationSettings, apiKey: String) throws {
    try TranscriptionContract.validate(settings: settings)
    let provider = settings.provider
    switch providerReadiness(provider, apiKey: apiKey) {
    case .ready:
      return
    case .missingAPIKey:
      throw MissingAPIKeyError(name: SecretKey(provider)?.rawValue ?? provider.title)
    case .missingLocalModel:
      throw NSError(
        domain: "Vhrase.Settings",
        code: 2,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Download the \(provider.title) model in Transcription or System before recording."
        ]
      )
    }
  }

  private func currentRecordingConfiguration() -> RecordingConfiguration {
    var resolvedSettings = settings
    resolvedSettings.adjustmentBaseURL = effectiveLLMBaseURL
    return RecordingConfiguration(
      settings: resolvedSettings,
      providerAPIKey: selectedProviderAPIKey,
      llmAPIKey: credentials.effectiveValue(.llmAPIKey)
    )
  }

  private var selectedProviderAPIKey: String {
    SecretKey(settings.provider).map(credentials.effectiveValue) ?? ""
  }

  private var selectedProviderReadiness: ProviderReadiness {
    providerReadiness(settings.provider, apiKey: selectedProviderAPIKey)
  }

  /// Applies one rule to readiness displays and recording validation: cloud providers need a credential, local ones the downloaded model.
  private func providerReadiness(_ provider: STTProvider, apiKey: String) -> ProviderReadiness {
    switch provider.location {
    case .cloud: apiKey.isEmpty ? .missingAPIKey : .ready
    case .local:
      localModels.store(for: provider)?.isInstalled == true ? .ready : .missingLocalModel
    }
  }

  private func persistSettings(previous: DictationSettings) {
    settingsStore.save(settings)
    localModels.settingsChanged(from: previous, to: settings)
    if settings.hotkeyPreset != previous.hotkeyPreset
      || settings.customHotkey != previous.customHotkey
    {
      registerHotkey()
    }
  }

  private func ensureCurrentRecording(_ recording: TranscriptionRecording) throws {
    try Task.checkCancellation()
    guard self.recording === recording else {
      throw CancellationError()
    }
  }

  private func finishRecordingStartup(
    _ recording: TranscriptionRecording,
    error: Error?
  ) {
    guard self.recording === recording else {
      return
    }
    releaseRecording()
    if let error {
      status = .failed(error.localizedDescription)
    } else if status == .preparing {
      status = .idle
    }
  }

  private func releaseRecording() {
    recordingTask?.cancel()
    recordingTask = nil
    recording?.cancel()
    recordingMeter.reset()
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
    guard canStartRecording else {
      return
    }

    activeWorkflow = .textPolish
    isWorkflowPopupDismissed = false
    audioInputPreview.stop()
    let target: FocusedTextTarget
    let polishSettings = settings
    let baseURL = effectiveLLMBaseURL
    let client = LLMAdjustmentClient(
      apiKey: credentials.effectiveValue(.llmAPIKey),
      baseURL: baseURL
    )
    do {
      try polishSettings.validateRestyle()
      target = try focusedTextService.capture()
      try client.validateConfiguration(model: polishSettings.adjustmentModel)
    } catch {
      status = .failed(error.localizedDescription)
      return
    }

    let id = UUID()
    textPolishID = id
    polishingOperation = .restyle(polishSettings.polishStyle)
    status = .adjusting
    notice = "Restyling text in \(target.app.name) with \(polishSettings.polishStyle.title)…"
    textPolishTask = Task { [weak self] in
      guard let self else { return }
      do {
        let polished = try await client.polish(
          target.text, as: .focusedText, settings: polishSettings, app: target.app)
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
        _ = try await self.inserter.paste(polished.output, keepOnClipboard: false)
        guard self.textPolishID == id else {
          return
        }
        self.textPolishTask = nil
        self.textPolishID = nil
        self.lastCompletion = .textRestyled(style: polishSettings.polishStyle)
        self.notice = self.lastCompletion.completionDetail
        self.status = .completed
        await self.recordPolishingCost(of: polished, baseURL: baseURL)
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
    notice = "Text polishing cancelled."
  }

  private func partialTranscriptHandler(
    for recording: TranscriptionRecording
  ) -> @Sendable (String) -> Void {
    { [weak self, weak recording] text in
      Task { @MainActor in
        guard let self, let recording, self.recording === recording else {
          return
        }
        self.liveTranscript = text
      }
    }
  }

  private func resetLiveRecordingState() {
    liveTranscript = ""
    recordingMeter.reset()
    lastCompletion = .transcript(.none)
    lastAdjustmentWarning = ""
  }

  private func finalizeTranscript(
    _ result: TranscriptionResult,
    adjustment: AdjustmentExecution,
    configuration: RecordingConfiguration,
    screenshot: Task<String?, Never>? = nil,
    timing: DictationTiming? = nil
  ) async throws {
    let settings = configuration.settings
    let targetApp = recordingTargetApp ?? appContext.targetApp()
    if let operation = settings.dictationPolishOperation {
      polishingOperation = adjustment == .provider ? operation : .refine
      status = .adjusting
      if adjustment == .localDemo {
        try await pauseForDemoVisibility()
      }
    }
    let finalized = try await TranscriptFinalizer(
      settings: settings,
      llmAPIKey: configuration.llmAPIKey,
      captureScreen: { app, resolution in
        if let screenshot { return await screenshot.value }
        return await LLMAdjustmentClient.captureDisplay(app, resolution)
      }
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
        transcriptionMode: settings.transcriptionModeTitle,
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
    if let refinement = finalized.refinement {
      await recordPolishingCost(of: refinement, baseURL: settings.adjustmentBaseURL)
    }
  }

  /// Adds one polish to today's estimated cost at the model's list price, after the result is delivered so a first price lookup never delays it; a polish whose usage or price is unknown stays uncounted.
  private func recordPolishingCost(of refinement: LLMRefinement, baseURL: String) async {
    guard let usage = refinement.usage else { return }
    do {
      guard
        let price = try await llmPrices.price(
          of: refinement.model, at: baseURL, apiKey: credentials.effectiveValue(.llmAPIKey))
      else { return }
      activityDays = activityStore.recordPolishing(
        costUSD: price.cost(of: usage), days: activityDays)
    } catch {
      logger.error("LLM price lookup failed: \(error.localizedDescription, privacy: .public)")
    }
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
      if !permissions.isReady(.accessibility) {
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
    recording = nil
    recordingConfiguration = nil
    recordingTargetApp = nil
    targetAppLabel = ""
  }

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
  case targetUnavailable

  var errorDescription: String? {
    switch self {
    case .targetUnavailable:
      "The app containing the text is no longer available. Nothing was replaced."
    }
  }
}
