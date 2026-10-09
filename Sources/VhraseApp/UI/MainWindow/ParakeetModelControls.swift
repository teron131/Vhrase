// Shows Parakeet's model, its one-time download, preparation, and readiness, and where text goes after on-device recognition.

import SwiftUI

struct ParakeetModelControls: View {
  @ObservedObject var appState: AppState
  @ObservedObject var model: ParakeetModelStore

  var body: some View {
    settingsRow(
      "Model",
      detail:
        "Runs through FluidAudio on the Neural Engine. Detects 25 European languages, including English; not Chinese or Cantonese."
    ) {
      Text("parakeet-tdt-0.6b-v3")
        .font(.callout.monospaced())
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    }

    settingsRow("On this Mac", detail: setupDetail) {
      setupControl
    }

    privacyNote
      .settingsRowStyle()
  }

  private var setupDetail: String {
    switch model.state {
    case .missing:
      "One-time \(ParakeetModelStore.downloadSizeLabel) download from Hugging Face. Recognition never uses the network afterwards."
    case .downloading(let fraction, let isCompiling):
      ParakeetModelStore.State.progressTitle(fraction: fraction, isCompiling: isCompiling)
    case .installed:
      model.isPreparing
        ? "Preparing for this Mac… The first time after a download or macOS update takes about 15 seconds."
        : "Ready to transcribe offline. Stored in Application Support › Vhrase › Models."
    case .failed(let message):
      message
    }
  }

  @ViewBuilder private var setupControl: some View {
    switch model.state {
    case .missing:
      Button {
        model.download()
      } label: {
        Label("Download \(ParakeetModelStore.downloadSizeLabel)", systemImage: "arrow.down.circle")
      }
      .buttonStyle(.borderedProminent)
    case .downloading(let fraction, let isCompiling):
      HStack(spacing: 10) {
        if isCompiling {
          ProgressView()
            .controlSize(.small)
        } else {
          ProgressView(value: fraction)
            .frame(width: 140)
        }
        Button("Cancel") {
          model.cancelDownload()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Parakeet model download")
    case .installed:
      HStack(spacing: 12) {
        if model.isPreparing {
          ProgressView()
            .controlSize(.small)
            .accessibilityLabel("Preparing the Parakeet model")
        } else {
          Label("Ready", systemImage: "checkmark.circle.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(VhraseTheme.statusSuccess)
        }
        Button("Remove") {
          appState.removeParakeetModel()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(model.isPreparing)
        .help("Deletes the downloaded model to free disk space")
      }
    case .failed:
      Button("Retry Download") {
        model.download()
      }
      .buttonStyle(.bordered)
    }
  }

  /// Keeps the on-device claim honest: optional LLM polishing still sends the transcript to its endpoint.
  @ViewBuilder private var privacyNote: some View {
    if appState.settings.adjustWithLLM {
      HStack(alignment: .center, spacing: 12) {
        Label(
          "Audio stays on this Mac, but LLM polishing is on: the transcript\(appState.settings.includeScreenshot ? " and a screenshot are" : " is") sent to \(llmHost).",
          systemImage: "exclamationmark.triangle"
        )
        .font(.caption)
        .foregroundStyle(VhraseTheme.statusWarning)
        .frame(maxWidth: .infinity, alignment: .leading)
        Button("Keep text on this Mac") {
          appState.updateSettings { $0.adjustWithLLM = false }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
    } else {
      Label("Audio and transcript stay on this Mac.", systemImage: "lock.fill")
        .font(.caption)
        .foregroundStyle(VhraseTheme.statusSuccess)
    }
  }

  private var llmHost: String {
    URL(string: appState.effectiveLLMBaseURL)?.host() ?? "the configured LLM endpoint"
  }
}
