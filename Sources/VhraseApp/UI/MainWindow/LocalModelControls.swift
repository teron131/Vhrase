// Shows a local provider's model, its one-time download, preparation, and readiness, and where text goes after local recognition.

import SwiftUI

struct LocalModelControls: View {
  @ObservedObject var appState: AppState
  @ObservedObject var store: LocalModelStore
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

  private var showsHuggingFace: Bool {
    store === appState.localModels.huggingFace
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
        Text(ParakeetModel.repository)
          .font(.callout.monospaced())
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }
    }
  }

  /// A download in flight belongs to the current ID, so the choice waits for it.
  @ViewBuilder private var huggingFaceModelRows: some View {
    let usesCustomModel =
      editsHuggingFaceModelID
      || appState.settings.huggingFaceModel != DictationSettings.defaultHuggingFaceModel
    settingsRow(
      "Model",
      detail: usesCustomModel
        ? "Runs through Hugging Face's transformers pipeline on the Apple GPU with the model named below."
        : "Runs through Hugging Face's transformers pipeline on the Apple GPU with the default model, \(DictationSettings.defaultHuggingFaceModel)."
    ) {
      Picker(
        "Model",
        selection: Binding(
          get: { usesCustomModel },
          set: { isCustom in
            editsHuggingFaceModelID = isCustom
            if !isCustom {
              appState.updateSettings {
                $0.huggingFaceModel = DictationSettings.defaultHuggingFaceModel
              }
            }
          }
        )
      ) {
        Text("Default").tag(false)
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
        "Any speech recognition model on Hugging Face that the transformers pipeline accepts, named owner/name."
    } catch {
      return error.localizedDescription
    }
  }

  private var setupDetail: String {
    switch store.state {
    case .missing:
      "One-time \(store.model.downloadSizeLabel.map { "\($0) " } ?? "")download from Hugging Face\(runtimeNote). Recognition never uses the network afterwards."
    case .downloading(let fraction, let isIndeterminate):
      LocalModelStore.State.progressTitle(fraction: fraction, isIndeterminate: isIndeterminate)
    case .installed:
      store.isPreparing
        ? "Preparing for this Mac… \(store.model.loadingNote)"
        : "Ready to transcribe offline. Stored in Application Support › Vhrase › Models."
    case .failed(let message):
      message
    }
  }

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

  /// Keeps the promise that audio stays on this Mac honest: optional LLM polishing still sends the transcript to its endpoint.
  @ViewBuilder private var privacyNote: some View {
    if appState.settings.afterTranscription.usesLLM {
      HStack(alignment: .center, spacing: 12) {
        Label(
          "Audio stays on this Mac, but dictation polishing sends the transcript\(appState.settings.includeScreenshot ? " and a screenshot" : "") to \(llmHost).",
          systemImage: "exclamationmark.triangle"
        )
        .font(.caption)
        .foregroundStyle(VhraseTheme.statusWarning)
        .frame(maxWidth: .infinity, alignment: .leading)
        Button("Keep text on this Mac") {
          appState.updateSettings { $0.afterTranscription = .off }
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
