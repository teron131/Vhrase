// Shows an on-device provider's model, its one-time download, preparation, and readiness, and where text goes after on-device recognition.

import SwiftUI

struct OnDeviceModelControls: View {
  @ObservedObject var appState: AppState
  @ObservedObject var store: OnDeviceModelStore
  /// Keeps the ID field open while it still holds the built-in model's ID, which is where a custom ID starts.
  @State private var editsHuggingFaceModelID = false

  var body: some View {
    modelRows

    settingsRow("On this Mac", detail: setupDetail) {
      setupControl
    }

    privacyNote
      .settingsRowStyle()
  }

  private var title: String {
    store.model.title
  }

  /// Hugging Face is the provider whose model the user chooses; Parakeet has one fixed model.
  private var showsHuggingFace: Bool {
    store === appState.huggingFaceModelStore
  }

  @ViewBuilder private var modelRows: some View {
    if showsHuggingFace {
      huggingFaceModelRows
    } else {
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
    }
  }

  /// Offers the built-in turbo model or any model ID the transformers pipeline accepts; a download in flight belongs to the current ID, so the choice waits for it.
  @ViewBuilder private var huggingFaceModelRows: some View {
    let usesCustomModel =
      editsHuggingFaceModelID
      || appState.settings.huggingFaceModel != HuggingFaceModelReference.whisperTurbo
    settingsRow(
      "Model",
      detail: usesCustomModel
        ? "Runs through Hugging Face's transformers pipeline on the Apple GPU with the model named below."
        : "Runs through Hugging Face's transformers pipeline on the Apple GPU. Whisper Large v3 Turbo is OpenAI's fastest large model, 1.6 GB at half precision, and covers about 100 languages including Chinese and Cantonese."
    ) {
      Picker(
        "Model",
        selection: Binding(
          get: { usesCustomModel },
          set: { isCustom in
            editsHuggingFaceModelID = isCustom
            if !isCustom {
              appState.updateSettings {
                $0.huggingFaceModel = HuggingFaceModelReference.whisperTurbo
              }
            }
          }
        )
      ) {
        Text("Whisper Large v3 Turbo").tag(false)
        Text("Custom").tag(true)
      }
      .labelsHidden()
      .fixedSize()
    }
    .disabled(store.isDownloading)

    if usesCustomModel {
      settingsRow("Model ID", detail: huggingFaceModelIDDetail) {
        TextField("Model ID", text: appState.settingsBinding(\.huggingFaceModel))
          .textFieldStyle(.roundedBorder)
          .labelsHidden()
          .font(.callout.monospaced())
          .frame(width: 260)
      }
      .disabled(store.isDownloading)
    }
  }

  private var huggingFaceModelIDDetail: String {
    do {
      _ = try HuggingFaceModelReference(appState.settings.huggingFaceModel)
      return
        "Any speech recognition model on Hugging Face that the transformers pipeline accepts, such as nvidia/parakeet-tdt-0.6b-v3 or openai/whisper-large-v3."
    } catch {
      return error.localizedDescription
    }
  }

  private var setupDetail: String {
    switch store.state {
    case .missing:
      "One-time \(store.model.downloadSizeLabel.map { "\($0) " } ?? "")download from Hugging Face\(runtimeNote). Recognition never uses the network afterwards."
    case .downloading(let fraction, let isIndeterminate):
      OnDeviceModelStore.State.progressTitle(fraction: fraction, isIndeterminate: isIndeterminate)
    case .installed:
      store.isPreparing
        ? "Preparing for this Mac… \(store.model.loadingNote)"
        : "Ready to transcribe offline. Stored in Application Support › Vhrase › Models."
    case .failed(let message):
      message
    }
  }

  /// Hugging Face models also need their Python environment, which uv builds once and every model shares.
  private var runtimeNote: String {
    showsHuggingFace ? ", plus about 1 GB of Python runtime that uv builds the first time" : ""
  }

  @ViewBuilder private var setupControl: some View {
    switch store.state {
    case .missing:
      Button {
        store.download()
      } label: {
        Label(store.downloadTitle, systemImage: "arrow.down.circle")
      }
      .buttonStyle(.borderedProminent)
    case .downloading(let fraction, let isIndeterminate):
      HStack(spacing: 10) {
        if isIndeterminate {
          ProgressView()
            .controlSize(.small)
        } else {
          ProgressView(value: fraction)
            .frame(width: 140)
        }
        Button("Cancel") {
          store.cancelDownload()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("\(title) model download")
    case .installed:
      HStack(spacing: 12) {
        if store.isPreparing {
          ProgressView()
            .controlSize(.small)
            .accessibilityLabel("Preparing the \(title) model")
        } else {
          Label("Ready", systemImage: "checkmark.circle.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(VhraseTheme.statusSuccess)
        }
        Button("Remove") {
          appState.removeLocalModel(store)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(store.isPreparing)
        .help("Deletes the downloaded model to free disk space")
      }
    case .failed:
      Button("Retry Download") {
        store.download()
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
