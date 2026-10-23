// Owns a five-entry test batch that replays recent dictations through Refine or Restyle, publishing independent outcomes while keeping cancellation and stale responses out of the view.

import Combine
import Foundation

@MainActor
final class PolishTest: ObservableObject {
  enum Outcome: Equatable, Sendable {
    case running
    case completed(LLMRefinement)
    case failed(String)
    case cancelled
  }

  enum State: Equatable {
    case idle
    case running([UUID: Outcome])
    case finished([UUID: Outcome])
    case failed(String)

    var outcomes: [UUID: Outcome] {
      switch self {
      case .running(let outcomes), .finished(let outcomes): outcomes
      case .idle, .failed: [:]
      }
    }

    var isRunning: Bool {
      if case .running = self { return true }
      return false
    }

    var completedCount: Int { outcomes.values.filter { $0 != .running }.count }
  }

  @Published private(set) var state = State.idle
  private var operation: Task<Void, Never>?

  static func recentHistory(_ history: [TranscriptHistoryItem]) -> [TranscriptHistoryItem] {
    Array(history.prefix(5))
  }

  /// Starts up to five concurrent requests; the returned task can be awaited, but this object owns cancellation.
  @discardableResult
  func start(
    history: [TranscriptHistoryItem], operation: PolishOperation, settings: DictationSettings,
    client: LLMAdjustmentClient
  ) -> Task<Void, Never> {
    clear()
    let items = Self.recentHistory(history)
    state = .running(Dictionary(uniqueKeysWithValues: items.map { ($0.id, Outcome.running) }))
    let operation = Task { [weak self] in
      guard !Task.isCancelled else { return }
      guard !items.isEmpty else {
        self?.state = .idle
        self?.operation = nil
        return
      }
      do {
        if case .restyle = operation { try settings.validateRestyle() }
        try client.validateConfiguration(model: settings.adjustmentModel)
      } catch {
        self?.state = .failed(error.localizedDescription)
        self?.operation = nil
        return
      }
      await withTaskGroup(of: (UUID, Outcome).self) { group in
        for item in items {
          group.addTask {
            do {
              try Task.checkCancellation()
              let result = try await client.replay(item, operation: operation, settings: settings)
              return (item.id, .completed(result))
            } catch {
              return (item.id, Task.isCancelled ? .cancelled : .failed(error.localizedDescription))
            }
          }
        }
        for await (id, outcome) in group {
          guard !Task.isCancelled, let self, case .running(var outcomes) = self.state else {
            group.cancelAll()
            break
          }
          outcomes[id] = outcome
          self.state = .running(outcomes)
        }
      }
      guard !Task.isCancelled, let self, case .running(let outcomes) = self.state else { return }
      self.state = .finished(outcomes)
      self.operation = nil
    }
    self.operation = operation
    return operation
  }

  func cancel() {
    operation?.cancel()
    operation = nil
    if case .running(let outcomes) = state {
      state = .finished(outcomes.mapValues { $0 == .running ? .cancelled : $0 })
    }
  }

  func clear() {
    cancel()
    state = .idle
  }

  deinit { operation?.cancel() }
}
