// Keeps model choice, shared vocabulary, writing preferences, and delivery together in priority order.

import SwiftUI

struct OutputView: View {
  @ObservedObject var appState: AppState

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        HStack(alignment: .center, spacing: 16) {
          pageHeader(
            MainWindowTab.output.title,
            description: "Choose the model, give it context, and shape your writing.",
            systemImage: MainWindowTab.output.systemImage
          )
          Spacer()
          customizationActions
        }

        polishingControls
        Divider()
        PolishPreferencesEditor(appState: appState)
        Divider()
        deliverySettings
        Divider()
        referenceEditors
      }
      .frame(maxWidth: 1040, alignment: .topLeading)
      .padding(32)
      .frame(maxWidth: .infinity, alignment: .top)
    }
    .toggleStyle(.switch)
    .disabled(appState.presentation.workflowControlsAreDisabled)
    .mainWindowEvents(appState: appState)
  }

  /// Keeps the chosen LLM and automatic-polishing behavior visible before the detailed writing preferences.
  private var polishingControls: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("LLM polishing")
          .font(.title2.weight(.semibold))
        Spacer()
        Toggle(
          "Polish new transcripts automatically", isOn: appState.settingsBinding(\.adjustWithLLM)
        )
        .fixedSize()
      }

      HStack(spacing: 16) {
        compactField("Model", text: appState.settingsBinding(\.adjustmentModel))
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

      Text("Double-tap polishing uses the same model, vocabulary, and writing preferences.")
        .font(.caption)
        .foregroundStyle(.secondary)

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

  /// Both editors are part of Output, with a stacked fallback when their labels need more width.
  private var referenceEditors: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .top, spacing: 24) {
        VocabularyEditor(appState: appState)
          .frame(minWidth: 330, maxWidth: .infinity)
        instructionsEditor
          .frame(minWidth: 330, maxWidth: .infinity)
      }
      VStack(alignment: .leading, spacing: 24) {
        VocabularyEditor(appState: appState)
        instructionsEditor
      }
    }
  }

  private var instructionsEditor: some View {
    editorTile(
      "Additional instructions",
      systemImage: "text.alignleft",
      text: appState.settingsBinding(\.adjustmentPrompt),
      height: 96,
      instruction:
        "Optional instructions for the LLM. These take priority over the writing preferences above.",
      placeholder: "Keep Jira issue keys unchanged. Use British spelling."
    )
  }

  private var deliverySettings: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Delivery")
        .font(.title2.weight(.semibold))
      settingsToggle(
        "Keep a copy on the clipboard",
        detail:
          "Vhrase returns text to the app where you started dictating. Keep the same text ready to paste elsewhere.",
        isOn: appState.settingsBinding(\.keepTranscriptOnClipboard)
      )
    }
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
