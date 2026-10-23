// Owns everything about the LLM pass in one place: whether dictation is refined or restyled, how Refine and Restyle read, the context and model they use, and whether OpenCC converts the Chinese in final transcripts.

import SwiftUI

struct PolishingView: View {
  @ObservedObject var appState: AppState
  let navigation: MainWindowNavigation
  @State private var isOpenCCInstallConfirmationPresented = false

  private var credentials: Credentials { appState.credentials }

  var body: some View {
    mainWindowPage {
      pageHeader(
        "Polishing",
        description:
          "Refine cleans up what you said. Restyle rewrites it in the style you pick, on a double-tap or after every dictation."
      )

      afterTranscriptionGroup
      PolishPreferencesEditor(appState: appState)
      contextGroup
      modelGroup
      chineseOutputGroup
    }
    .disabled(appState.presentation.workflowControlsAreDisabled)
    .mainWindowEvents(appState: appState, blocksEscape: isOpenCCInstallConfirmationPresented)
    .openCCInstallConfirmation(
      isPresented: $isOpenCCInstallConfirmationPresented, setup: appState.openCCSetup)
  }

  private var afterTranscriptionGroup: some View {
    settingsGroup(
      "Dictation",
      footer:
        "Double-tap always restyles, even when this is Off. Restyled dictation has no undo; the original stays on Dictation under Before Vhrase cleanup."
    ) {
      settingsRow("After transcription") {
        PillPicker(
          title: "After transcription", selection: appState.settingsBinding(\.afterTranscription),
          options: DictationPolishing.allCases, label: { $0.title }, fillsWidth: true
        )
        .frame(width: 320)
      }

      if appState.settings.afterTranscription.usesLLM {
        settingsToggle(
          "Use local cleanup if the LLM fails",
          detail:
            "If the model fails, delivers a locally tidied transcript instead of the raw one.",
          isOn: appState.settingsBinding(\.useLocalAdjustmentFallback)
        )
      }
    }
  }

  private var contextGroup: some View {
    settingsGroup("Context") {
      settingsToggle(
        "Use screen context",
        detail:
          "Adds a screenshot to dictation and double-tap requests so the model can spell names it sees. Restyle tries on recent dictations never attach your screen.",
        isOn: appState.settingsBinding(\.includeScreenshot)
      )

      if appState.settings.includeScreenshot {
        screenshotResolutionRow
      }
    }
  }

  private var screenshotResolutionRow: some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Screenshot size")
        Text(
          "Longest side of the screenshot. Smaller images reach the model sooner, but small text and unusual names blur."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
      StepSlider(
        title: "Screenshot size",
        options: ScreenshotResolution.allCases,
        selection: appState.settingsBinding(\.screenshotResolution),
        label: \.title
      )
      ScreenshotSizePreview(resolution: appState.settings.screenshotResolution)
    }
    .settingsRowStyle()
  }

  private var modelGroup: some View {
    let usesEnvironmentURL = credentials.usesEnvironmentLLMBaseURL
    let modelIsMissing =
      appState.settings.adjustmentModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    return settingsGroup("LLM", footer: "Works with any OpenAI-compatible API.") {
      settingsRow(
        "Endpoint",
        detail: usesEnvironmentURL
          ? "Read from LLM_BASE_URL in your environment, which overrides the saved endpoint."
          : "The API's base URL, such as https://ai-gateway.vercel.sh/v1."
      ) {
        TextField(
          "Endpoint",
          text: Binding(
            get: { appState.effectiveLLMBaseURL },
            set: { value in
              guard !usesEnvironmentURL else { return }
              appState.updateSettings { $0.adjustmentBaseURL = value }
            }
          )
        )
        .textFieldStyle(.roundedBorder)
        .labelsHidden()
        .frame(width: 320)
        .disabled(usesEnvironmentURL)
      }

      HStack(alignment: .center, spacing: 20) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Model")
          Text(
            modelIsMissing
              ? "Enter a model to polish with."
              : "Checking access sends only a tiny “Reply with OK” request."
          )
          .font(.caption)
          .foregroundStyle(modelIsMissing ? VhraseTheme.statusFailure : Color.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        HStack(spacing: 10) {
          TextField("Model", text: appState.settingsBinding(\.adjustmentModel))
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .frame(width: 200)
          Button {
            appState.checkLLMModelAccess()
          } label: {
            HStack(spacing: 6) {
              if appState.isCheckingLLMModelAccess {
                ProgressView()
                  .controlSize(.small)
              } else {
                Image(systemName: "checkmark.seal")
              }
              Text(appState.isCheckingLLMModelAccess ? "Checking model…" : "Check model access")
            }
          }
          .buttonStyle(.bordered)
          .disabled(
            appState.isCheckingLLMModelAccess || modelIsMissing
              || credentials.effectiveValue(.llmAPIKey).isEmpty)
        }
        .fixedSize()
      }
      .settingsRowStyle()

      CredentialSummaryRow(
        key: .llmAPIKey, credentials: credentials, purpose: "polish transcripts",
        open: { navigation.openCredential(.llmAPIKey) })
    }
  }

  private var chineseOutputGroup: some View {
    settingsGroup("Chinese output") {
      settingsToggle(
        "Convert to Traditional Chinese",
        detail: "Rewrites the Chinese in each final transcript with OpenCC, after polishing.",
        isOn: appState.settingsBinding(\.convertChineseOutput)
      )
      if appState.settings.convertChineseOutput {
        openCCRow
      }
    }
  }

  private var openCCRow: some View {
    let setup = appState.openCCSetup
    let detail =
      if setup.isInstalled {
        "Installed on this Mac."
      } else if setup.installation == .installing {
        "Installing OpenCC with Homebrew…"
      } else if let failure = setup.failureMessage {
        failure
      } else if setup.canInstall {
        "Install OpenCC to convert Chinese."
      } else {
        "OpenCC installs with Homebrew, which this Mac doesn't have yet."
      }
    return settingsRow("OpenCC", detail: detail) {
      if setup.isInstalled {
        Label("Installed", systemImage: "checkmark.circle.fill")
          .font(.caption.weight(.medium))
          .foregroundStyle(VhraseTheme.statusSuccess)
      } else if setup.installation == .installing {
        ProgressView()
          .controlSize(.small)
          .accessibilityLabel("Installing OpenCC")
      } else {
        Button(setup.nextStepTitle) {
          setup.takeNextStep { isOpenCCInstallConfirmationPresented = true }
        }
        .buttonStyle(.bordered)
      }
    }
  }
}

extension View {
  /// Asks before running Homebrew, wherever an OpenCC install starts: Chinese output on Polishing or the setup summary on System.
  func openCCInstallConfirmation(isPresented: Binding<Bool>, setup: OpenCCSetup) -> some View {
    confirmationDialog("Install OpenCC?", isPresented: isPresented, titleVisibility: .visible) {
      Button("Install with Homebrew") { setup.install() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "Vhrase will run “brew install opencc”. Homebrew may download OpenCC and its required packages."
      )
    }
  }
}
