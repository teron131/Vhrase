// Keeps model choice, writing preferences, shared vocabulary, instructions, and delivery together in priority order.

import SwiftUI

struct OutputView: View {
  @ObservedObject var appState: AppState

  var body: some View {
    mainWindowPage {
      pageHeader(
        MainWindowTab.output.title,
        description: "Choose the model, give it context, and shape your writing."
      ) {
        customizationActions
      }

      polishingControls
      PolishPreferencesEditor(appState: appState)

      settingsGroup("Shared vocabulary") {
        VocabularyEditor(appState: appState)
          .settingsRowStyle()
      }

      settingsGroup("Additional instructions") {
        instructionsEditor
          .settingsRowStyle()
      }

      settingsGroup("Delivery") {
        settingsToggle(
          "Keep a copy on the clipboard",
          detail:
            "Vhrase returns text to the app where you started dictating. Keep the same text ready to paste elsewhere.",
          isOn: appState.settingsBinding(\.keepTranscriptOnClipboard)
        )
      }
    }
    .disabled(appState.presentation.workflowControlsAreDisabled)
    .mainWindowEvents(appState: appState)
  }

  /// Keeps the chosen LLM and automatic-polishing behavior visible before the detailed writing preferences.
  private var polishingControls: some View {
    settingsGroup(
      "LLM polishing",
      footer: "Double-tap polishing uses the same model, vocabulary, and writing preferences."
    ) {
      settingsToggle(
        "Polish new transcripts automatically",
        detail: "Run each finished dictation through the model before Vhrase delivers it.",
        isOn: appState.settingsBinding(\.adjustWithLLM)
      )

      settingsRow("Model", detail: "Uses the endpoint and key in System.") {
        HStack(spacing: 10) {
          TextField("Model", text: appState.settingsBinding(\.adjustmentModel))
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .frame(width: 220)
          Button {
            appState.checkLLMModelAccess()
          } label: {
            Label(
              appState.isCheckingLLMModelAccess ? "Checking model…" : "Check model access",
              systemImage: "checkmark.seal"
            )
          }
          .buttonStyle(.bordered)
          .disabled(appState.isCheckingLLMModelAccess)
        }
      }

      settingsToggle(
        "Use screen context",
        detail:
          "Send a screenshot to the configured LLM endpoint when polishing text or a transcript.",
        isOn: appState.settingsBinding(\.includeScreenshot)
      )

      if appState.settings.adjustWithLLM {
        settingsToggle(
          "Use local cleanup if the LLM fails",
          detail: "Return a locally normalized transcript instead of blocking delivery.",
          isOn: appState.settingsBinding(\.useLocalAdjustmentFallback)
        )
      }
    }
  }

  private var instructionsEditor: some View {
    editorTile(
      "Additional instructions",
      text: appState.settingsBinding(\.adjustmentPrompt),
      height: 96,
      instruction:
        "Optional instructions for the LLM. These take priority over the writing preferences above.",
      placeholder: "Keep Jira issue keys unchanged. Use British spelling."
    )
  }

  private var customizationActions: some View {
    HStack(spacing: 8) {
      Button {
        appState.importCustomization()
      } label: {
        Label("Import", systemImage: "square.and.arrow.down")
      }
      Button {
        appState.exportCustomization()
      } label: {
        Label("Export", systemImage: "square.and.arrow.up")
      }
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
    .help("Import or export language, vocabulary, and writing preferences")
  }
}
