// Exercises setup operations that complete after a model selection changes, without files, downloads, or model runtimes.

import Foundation

@main
@MainActor
struct OnDeviceModelStoreCheck {
  static func main() async throws {
    let first = ControlledModel(title: "First")
    let second = ControlledModel(title: "Second")
    let store = OnDeviceModelStore(model: first)
    store.prepare()
    await waitUntil { await first.loading.starts == 1 }
    try await store.remove()
    let removalsWhilePreparing = await first.removal.starts
    precondition(removalsWhilePreparing == 0, "Removal must wait for preparation")

    store.select(second)
    precondition(!store.isPreparing, "Preparation belongs to the selected model")
    store.prepare()
    store.prepare()
    await waitUntil { await second.loading.starts == 1 }
    await first.loading.finish()
    await settle()
    precondition(store.isPreparing, "An old preparation must not finish the new model's progress")
    await second.loading.finish()
    await waitUntil { @MainActor in !store.isPreparing }
    let secondLoads = await second.loading.starts
    precondition(secondLoads == 1)

    let removal = Task { try await store.remove() }
    await waitUntil { await second.removal.starts == 1 }
    store.select(first)
    await second.removal.finish()
    try await removal.value
    precondition(
      store.state == .installed, "Removing the previous model must not mark the new model missing")
    print("on-device model store lifecycle ok")
  }

  private static func waitUntil(_ condition: () async -> Bool) async {
    for _ in 0..<200 {
      if await condition() { return }
      try? await Task.sleep(for: .milliseconds(5))
    }
    preconditionFailure("Model operation did not reach the expected state")
  }

  private static func settle() async {
    for _ in 0..<20 { await Task.yield() }
  }
}

private final class ControlledModel: OnDeviceModel, SpeechToTextClient, Sendable {
  let title: String
  let downloadSizeLabel: String? = nil
  let requiredFreeBytes: Int64? = nil
  let loadingNote = "Controlled preparation"
  let isInstalled = true
  let loading = ModelOperation()
  let removal = ModelOperation()
  var recognizer: any SpeechToTextClient { self }

  init(title: String) { self.title = title }

  func load() async throws { await loading.run() }
  func remove() async throws { await removal.run() }

  func download(progress: @escaping @Sendable (Double, Bool) -> Void) async throws {
    preconditionFailure("This check must not download")
  }

  func transcribe(fileURL: URL, settings: DictationSettings) async throws -> TranscriptionResult {
    preconditionFailure("This check must not transcribe")
  }
}

private actor ModelOperation {
  private(set) var starts = 0
  private var completion: CheckedContinuation<Void, Never>?

  func run() async {
    await withCheckedContinuation { continuation in
      starts += 1
      completion = continuation
    }
  }

  func finish() {
    completion?.resume()
    completion = nil
  }
}
