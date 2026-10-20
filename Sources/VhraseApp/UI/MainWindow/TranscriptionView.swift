// Owns the speech-to-text choice: provider, mode, and language, the selected provider's setup and options, and a short recognition test that ends when its window or destination is left.

import SwiftUI

struct TranscriptionView: View {
  @ObservedObject var appState: AppState
  let navigation: MainWindowNavigation
  private var presentation: DictationPresentation { appState.presentation }
  private var provider: STTProvider { appState.settings.provider }

  var body: some View {
    mainWindowPage {
      pageHeader(
        "Transcription",
        description: "Choose who turns your speech into text, and tune how they hear it."
      )

      if let issue = presentation.transcriptionConfigurationIssue {
        // A list over the provider's limit is fixed on Vocabulary, or by choosing another provider here.
        let isVocabularyIssue = issue == presentation.vocabularyIssue
        NoticeCard(
          issue, systemImage: "exclamationmark.triangle", color: VhraseTheme.statusFailure,
          title: "Recording is blocked",
          actionTitle: isVocabularyIssue ? "Open Vocabulary" : nil,
          action: isVocabularyIssue ? { navigation.open(.vocabulary) } : nil)
      }

      serviceGroup
        .disabled(appState.transcriptionTest.state.isActive)

      settingsGroup(provider.title) {
        providerSetup
        providerOptions
      }
      .disabled(appState.transcriptionTest.state.isActive)

      settingsGroup("Test") {
        TranscriptionTestView(appState: appState, test: appState.transcriptionTest)
          .settingsRowStyle()
      }
    }
    .disabled(presentation.workflowControlsAreDisabled)
    .mainWindowEvents(appState: appState, onDeactivate: { appState.transcriptionTest.cancel() })
    .onDisappear { appState.transcriptionTest.cancel() }
  }

  private var serviceGroup: some View {
    settingsGroup("Service", footer: serviceFooter) {
      ForEach(ProviderLocation.allCases) { location in
        settingsRow(location.title, detail: providerDetail(for: location)) {
          ProviderPicker(
            selection: appState.settingsBinding(\.provider),
            providers: location.providers,
            style: .segmented
          )
          .fixedSize()
        }
      }
      settingsRow(
        "Mode",
        detail: provider.location == .local
          ? "Transcribes on this Mac once you stop recording."
          : provider.availableModes.contains(.realtime)
            ? "Upload transcribes after you stop. Realtime transcribes while you speak."
            : "\(provider.title) transcribes after you stop; realtime isn't available."
      ) {
        TranscriptionModePicker(
          selection: appState.settingsBinding(\.transcriptionMode),
          provider: provider,
          enabledModes: provider.availableModes
        )
        .fixedSize()
      }
      languageRow
    }
  }

  /// Describes the chosen provider in its own location's row and what choosing the other location means.
  private func providerDetail(for location: ProviderLocation) -> String {
    if provider.location == location {
      return provider.detail
    }
    return switch location {
    case .cloud: "Sends your recording to the provider; each needs its API key."
    case .local: "Recognizes speech on this Mac after a one-time model download; no API key."
    }
  }

  private var serviceFooter: String? {
    switch provider {
    case .gemini:
      "Audio goes directly to Google after you stop, with interaction storage turned off."
    case .openAI:
      "Audio goes directly to OpenAI after you stop."
    case .vercel:
      "Audio goes to Vercel AI Gateway after you stop, which forwards it to the model's provider."
    case .parakeet, .huggingFace:
      "No audio leaves this Mac."
    case .xai, .elevenLabs:
      nil
    }
  }

  /// The language the selected provider expects, in that provider's own terms, since each one reads it differently.
  @ViewBuilder private var languageRow: some View {
    switch provider {
    case .gemini:
      settingsRow(
        "Language hints",
        detail:
          "Optional BCP-47 codes separated by commas, such as en-US, yue-Hant-HK. Leave blank for automatic detection and code-switching."
      ) {
        TextField("Language hints", text: appState.settingsBinding(\.geminiLanguageHints))
          .textFieldStyle(.roundedBorder)
          .labelsHidden()
          .frame(width: 220)
      }
    case .parakeet:
      automaticLanguageRow(
        "Parakeet detects the spoken language automatically among its 25 European languages, so no code is needed."
      )
    case .vercel:
      automaticLanguageRow(
        "The gateway forwards no language hint, so the model detects the spoken language.")
    case .xai:
      languageCodeRow(
        "Grok detects the spoken language itself. This code, such as en, only sets how numbers and currency are formatted when that option is on."
      )
    case .huggingFace:
      languageCodeRow(
        "Whisper models take a language code such as en, yue, or zh; leave blank to detect it. Other models detect the language themselves."
      )
    case .elevenLabs, .openAI:
      languageCodeRow(
        "Use a language code such as en, yue, or zh. Leave blank for automatic detection.")
    }
  }

  /// The language row for a provider that takes no language code.
  private func automaticLanguageRow(_ detail: String) -> some View {
    settingsRow("Language", detail: detail) {
      Text("Automatic")
        .foregroundStyle(.secondary)
    }
  }

  /// The language row for a provider that reads the shared language code.
  private func languageCodeRow(_ detail: String) -> some View {
    settingsRow("Language", detail: detail) {
      TextField("Language", text: appState.settingsBinding(\.language))
        .textFieldStyle(.roundedBorder)
        .labelsHidden()
        .frame(width: 220)
    }
  }

  /// What the selected provider needs before it can run: its key, which System stores, or its on-device model.
  @ViewBuilder private var providerSetup: some View {
    switch provider {
    case .parakeet:
      OnDeviceModelControls(appState: appState, store: appState.parakeetModelStore)
    case .huggingFace:
      OnDeviceModelControls(appState: appState, store: appState.huggingFaceModelStore)
    case .xai, .elevenLabs, .gemini, .openAI, .vercel:
      if let key = SecretKey(provider) {
        CredentialSummaryRow(
          key: key, credentials: appState.credentials,
          purpose: "transcribe with \(provider.title)",
          open: { navigation.openCredential(key) })
      }
    }
  }

  @ViewBuilder
  private var providerOptions: some View {
    switch provider {
    case .parakeet, .huggingFace:
      EmptyView()
    case .openAI:
      settingsRow(
        "Model",
        detail: "OpenAI's recorded-speech model."
      ) {
        Text(OpenAITranscriptionContract.modelID)
          .font(.callout.monospaced())
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }
    case .vercel:
      settingsRow(
        "Model",
        detail:
          "Any transcription model in the gateway's catalog, such as \(DictationSettings.defaultVercelModel), openai/gpt-transcribe, or google/gemini-3.5-transcribe."
      ) {
        TextField("Model", text: appState.settingsBinding(\.vercelModel))
          .textFieldStyle(.roundedBorder)
          .labelsHidden()
          .font(.callout.monospaced())
          .frame(width: 260)
      }
    case .gemini:
      settingsToggle(
        "Smart transcription",
        detail:
          "Removes fillers, resolves spoken corrections, and formats paragraphs and lists. Turn it off to stay closer to your exact words.",
        isOn: appState.settingsBinding(\.geminiSmartTranscription))
      if appState.settings.geminiSmartTranscription, appState.settings.adjustWithLLM {
        HStack(alignment: .center, spacing: 12) {
          Label(
            "Automatic polishing in Refinement is also on, so the Smart transcript gets rewritten a second time.",
            systemImage: "exclamationmark.triangle"
          )
          .font(.caption)
          .foregroundStyle(VhraseTheme.statusWarning)
          .frame(maxWidth: .infinity, alignment: .leading)
          Button("Use Smart only") {
            appState.updateSettings { $0.adjustWithLLM = false }
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
        .settingsRowStyle()
      }
    case .xai:
      settingsToggle(
        "Keep filler words",
        detail: "Keeps “um” and “uh” in the transcript. Off removes them during recognition.",
        isOn: appState.settingsBinding(\.includeFillerWords))
      settingsToggle(
        "Format numbers and currency",
        detail:
          "Writes “one hundred dollars” as “$100”, using the language code above.",
        isOn: appState.settingsBinding(\.xaiFormatText))

      if appState.settings.transcriptionMode == .realtime {
        settingsSlider(
          "Speech detection threshold",
          detail:
            "Lower values catch quiet speech but may pick up background noise. 0 turns the gate off; the default is 0.08.",
          value: appState.settingsBinding(\.xaiVADThreshold),
          in: 0...1,
          step: 0.01,
          valueLabel: appState.settings.xaiVADThreshold.formatted(
            .number.precision(.fractionLength(2)))
        )
        settingsStepper(
          "Endpointing",
          detail: "How long a pause must last before Grok ends a phrase.",
          value: appState.settingsBinding(\.xaiRealtimeEndpointing),
          in: 0...5000,
          step: 100,
          valueLabel: "\(appState.settings.xaiRealtimeEndpointing) ms"
        )
        settingsToggle(
          "Smart Turn",
          detail:
            "Waits for a complete thought before ending a phrase. It changes timing, not wording.",
          isOn: appState.settingsBinding(\.xaiSmartTurnEnabled))

        if appState.settings.xaiSmartTurnEnabled {
          settingsSlider(
            "Smart Turn threshold",
            value: appState.settingsBinding(\.xaiSmartTurnThreshold),
            in: 0...1,
            step: 0.05,
            valueLabel: appState.settings.xaiSmartTurnThreshold.formatted(
              .number.precision(.fractionLength(2)))
          )
          settingsStepper(
            "Smart Turn timeout",
            value: appState.settingsBinding(\.xaiSmartTurnTimeout),
            in: 1...5000,
            step: 100,
            valueLabel: "\(appState.settings.xaiSmartTurnTimeout) ms"
          )
        }
      }
    case .elevenLabs:
      settingsRow("Model") {
        Text(
          appState.settings.transcriptionMode == .realtime
            ? ElevenLabsTranscriptionContract.realtimeModelID
            : ElevenLabsTranscriptionContract.uploadModelID
        )
        .font(.callout.monospaced())
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
      }

      settingsToggle(
        "Clean up spoken disfluencies",
        detail: "Uses Scribe's non-verbatim mode for more readable text.",
        isOn: appState.settingsBinding(\.elevenLabsNoVerbatim))

      if appState.settings.transcriptionMode == .realtime {
        settingsRow("Commit strategy") {
          Picker("Commit strategy", selection: appState.settingsBinding(\.elevenLabsCommitStrategy))
          {
            ForEach(ElevenLabsCommitStrategy.allCases) { strategy in
              Text(strategy.title).tag(strategy)
            }
          }
          .labelsHidden()
          .fixedSize()
        }

        if appState.settings.elevenLabsCommitStrategy == .vad {
          settingsStepper(
            "VAD silence",
            value: appState.settingsBinding(\.elevenLabsVADSilenceThreshold),
            in: 0.3...3,
            step: 0.1,
            valueLabel: String(format: "%.1f s", appState.settings.elevenLabsVADSilenceThreshold)
          )
          settingsSlider(
            "VAD threshold",
            value: appState.settingsBinding(\.elevenLabsVADThreshold),
            in: 0.1...0.9,
            step: 0.05,
            valueLabel: appState.settings.elevenLabsVADThreshold.formatted(
              .number.precision(.fractionLength(2)))
          )
          settingsStepper(
            "Minimum speech",
            value: appState.settingsBinding(\.elevenLabsMinSpeechDuration),
            in: 50...2000,
            step: 50,
            valueLabel: "\(appState.settings.elevenLabsMinSpeechDuration) ms"
          )
          settingsStepper(
            "Minimum silence",
            value: appState.settingsBinding(\.elevenLabsMinSilenceDuration),
            in: 50...2000,
            step: 50,
            valueLabel: "\(appState.settings.elevenLabsMinSilenceDuration) ms"
          )
        }
      }
    }
  }
}
