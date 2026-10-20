// Owns how a transcript is polished: when the LLM runs and what context it sees, which endpoint and model it uses, and the local Chinese conversion every transcript passes through; Writing holds how the polished text should read.

import SwiftUI

struct RefinementView: View {
  @ObservedObject var appState: AppState
  let navigation: MainWindowNavigation
  @State private var isOpenCCInstallConfirmationPresented = false

  private var credentials: Credentials { appState.credentials }

  var body: some View {
    mainWindowPage {
      pageHeader(
        "Refinement",
        description: "Polish the transcript with an LLM before it reaches your app."
      )

      polishingGroup
      modelGroup
      chineseOutputGroup
    }
    .disabled(appState.presentation.workflowControlsAreDisabled)
    .mainWindowEvents(appState: appState, blocksEscape: isOpenCCInstallConfirmationPresented)
    .openCCInstallConfirmation(
      isPresented: $isOpenCCInstallConfirmationPresented, appState: appState)
  }

  private var polishingGroup: some View {
    settingsGroup(
      "Polishing",
      footer:
        "Double-tap polishing uses the same model, context, and writing preferences, even when automatic polishing is off."
    ) {
      settingsToggle(
        "Polish new transcripts automatically",
        detail: "Runs each finished dictation through the model before Vhrase delivers it.",
        isOn: appState.settingsBinding(\.adjustWithLLM)
      )

      settingsToggle(
        "Use screen context",
        detail:
          "Sends a screenshot of the screen you're working on with each polish, so the model can spell the names it sees.",
        isOn: appState.settingsBinding(\.includeScreenshot)
      )

      if appState.settings.includeScreenshot {
        screenshotResolutionRow
      }

      if appState.settings.adjustWithLLM {
        settingsToggle(
          "Use local cleanup if the LLM fails",
          detail:
            "If the model fails, delivers a locally tidied transcript instead of the raw one.",
          isOn: appState.settingsBinding(\.useLocalAdjustmentFallback)
        )
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
    let state = appState.openCCInstallationState
    let isInstalled = ChineseTextConverter.isAvailable
    let detail =
      if isInstalled {
        "OpenCC converts Chinese in every final transcript, after polishing."
      } else if state == .installing {
        "Installing OpenCC with Homebrew…"
      } else if let failure = state.failureMessage {
        failure
      } else if appState.canInstallOpenCC {
        "Install OpenCC to convert Chinese in every final transcript."
      } else {
        "OpenCC installs with Homebrew, which this Mac doesn't have yet."
      }
    return settingsGroup("Chinese output") {
      settingsRow("Hong Kong Traditional Chinese", detail: detail) {
        if isInstalled {
          Label("Installed", systemImage: "checkmark.circle.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(VhraseTheme.statusSuccess)
        } else if state == .installing {
          ProgressView()
            .controlSize(.small)
            .accessibilityLabel("Installing OpenCC")
        } else if appState.canInstallOpenCC {
          Button(state.failureMessage == nil ? "Install OpenCC" : "Retry Install") {
            isOpenCCInstallConfirmationPresented = true
          }
          .buttonStyle(.bordered)
        } else {
          Button("Get Homebrew") { appState.openHomebrewSetup() }
            .buttonStyle(.bordered)
        }
      }
    }
  }
}

extension View {
  /// Asks before running Homebrew, wherever an OpenCC install starts: Chinese output on Refinement or the setup summary on System.
  func openCCInstallConfirmation(isPresented: Binding<Bool>, appState: AppState) -> some View {
    confirmationDialog("Install OpenCC?", isPresented: isPresented, titleVisibility: .visible) {
      Button("Install with Homebrew") { appState.installOpenCC() }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "Vhrase will run “brew install opencc”. Homebrew may download OpenCC and its required packages."
      )
    }
  }
}
