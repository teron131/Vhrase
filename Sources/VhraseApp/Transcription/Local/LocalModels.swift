// Owns the app's two local model stores and decides what stays loaded: the selected provider's model warms up, every Hugging Face model shares one recognizer so only one is ever in memory, and switching away from Hugging Face unloads it.

import Foundation

@MainActor
final class LocalModels {
  let parakeet = LocalModelStore(model: ParakeetModel())
  let huggingFace: LocalModelStore
  private let huggingFaceRecognizer = HuggingFaceRecognizer()
  private var provider: STTProvider

  init(settings: DictationSettings) {
    provider = settings.provider
    huggingFace = LocalModelStore(
      model: HuggingFaceModel(id: settings.huggingFaceModel, recognizer: huggingFaceRecognizer))
  }

  func store(for provider: STTProvider) -> LocalModelStore? {
    switch provider {
    case .parakeet: parakeet
    case .huggingFace: huggingFace
    case .xai, .elevenLabs, .gemini, .openAI, .vercel: nil
    }
  }

  /// `nil` while a cloud provider is selected.
  var selected: LocalModelStore? {
    store(for: provider)
  }

  /// Loads the selected provider's model so it overlaps the user's speech.
  func prepareSelected() {
    selected?.prepare()
  }

  func settingsChanged(from previous: DictationSettings, to settings: DictationSettings) {
    provider = settings.provider
    if previous.provider == .huggingFace, settings.provider != .huggingFace {
      huggingFace.cancelPreparation()
      Task { [weak self] in
        // Switching back to Hugging Face before this runs keeps its model loaded.
        guard let self, self.provider != .huggingFace else { return }
        await self.huggingFaceRecognizer.unload()
      }
    }
    let huggingFaceModelChanged = settings.huggingFaceModel != previous.huggingFaceModel
    if huggingFaceModelChanged {
      huggingFace.select(
        HuggingFaceModel(id: settings.huggingFaceModel, recognizer: huggingFaceRecognizer))
    }
    if settings.provider != previous.provider || huggingFaceModelChanged {
      prepareSelected()
    }
  }

  func cancelDownloadsAndPreparation() {
    parakeet.cancelDownload()
    huggingFace.cancelDownload()
    huggingFace.cancelPreparation()
  }
}
