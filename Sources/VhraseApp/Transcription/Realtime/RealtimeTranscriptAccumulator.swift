// Accumulates provider events into one ordered realtime transcript and resolves terminal waiters.

import Foundation

actor RealtimeTranscriptAccumulator {
  private let providerName: String
  private var finalSegments: [String] = []
  private var xaiLockedUtterance = ""
  private var latestPartial = ""
  private var doneText: String?
  private var duration: Double?
  private var error: Error?
  private var resolvedResult: TranscriptionResult?
  private var isElevenLabsFinishCommitPending = false
  private var elevenLabsFinishResolutionTask: Task<Void, Never>?
  private var continuations: [UUID: CheckedContinuation<TranscriptionResult, Error>] = [:]
  private let onPartialTranscript: (@Sendable (String) -> Void)?
  private let elevenLabsFinishSettleNanoseconds: UInt64

  init(
    providerName: String,
    onPartialTranscript: (@Sendable (String) -> Void)?,
    elevenLabsFinishSettleNanoseconds: UInt64 = 350_000_000
  ) {
    self.providerName = providerName
    self.onPartialTranscript = onPartialTranscript
    self.elevenLabsFinishSettleNanoseconds = elevenLabsFinishSettleNanoseconds
  }

  func handleXAI(_ event: XAIRealtimeEvent) -> RealtimeEventOutcome {
    switch event.type {
    case "transcript.partial":
      if let text = event.text, !text.isEmpty {
        // Chunk-final text stays replaceable within the current utterance.
        // xAI's speech-final text is the complete stitched utterance and is committed once.
        if event.speech_final == true {
          appendFinal(text)
          xaiLockedUtterance = ""
          latestPartial = ""
        } else if event.is_final == true {
          xaiLockedUtterance = mergeIncrementalText(xaiLockedUtterance, text)
          latestPartial = ""
        } else {
          latestPartial = text
        }
        publishCurrentText()
      }
    case "transcript.done":
      if let text = event.text?.trimmingCharacters(in: .whitespacesAndNewlines),
        !text.isEmpty
      {
        doneText = text
      }
      duration = event.duration
      resolve()
      return .completed
    case "error":
      failMessage(event.message ?? "xAI realtime transcription failed.")
      return .failed
    default:
      break
    }
    return .continueReceiving
  }

  func handleElevenLabs(_ event: ElevenLabsRealtimeEvent) -> RealtimeEventOutcome {
    if event.isError {
      let detail = event.error ?? event.text ?? "Realtime transcription failed."
      failMessage("ElevenLabs realtime \(event.message_type): \(detail)")
      return .failed
    }

    switch event.message_type {
    case "partial_transcript":
      if isElevenLabsFinishCommitPending {
        elevenLabsFinishResolutionTask?.cancel()
        elevenLabsFinishResolutionTask = nil
      }
      latestPartial = event.text ?? latestPartial
      publishCurrentText()
    case "committed_transcript", "committed_transcript_with_timestamps":
      if let text = event.text, !text.isEmpty {
        appendFinal(text)
        latestPartial = ""
      }
      publishCurrentText()
      if isElevenLabsFinishCommitPending {
        scheduleElevenLabsFinishResolution()
      }
    default:
      break
    }
    return .continueReceiving
  }

  /// Starts a bounded final drain because VAD and explicit commits share the same uncorrelated event type.
  func beginElevenLabsFinishCommit() {
    isElevenLabsFinishCommitPending = true
  }

  func fail(_ error: Error) {
    guard self.error == nil, resolvedResult == nil else {
      return
    }
    elevenLabsFinishResolutionTask?.cancel()
    elevenLabsFinishResolutionTask = nil
    self.error = error
    let pending = continuations.values
    continuations.removeAll()
    for continuation in pending {
      continuation.resume(throwing: error)
    }
  }

  func waitForDone() async throws -> TranscriptionResult {
    if let resolvedResult {
      return resolvedResult
    }
    if let error {
      throw error
    }
    if Task.isCancelled {
      throw CancellationError()
    }

    let id = UUID()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        if Task.isCancelled {
          continuation.resume(throwing: CancellationError())
        } else {
          continuations[id] = continuation
        }
      }
    } onCancel: {
      Task {
        await self.cancelWaiter(id)
      }
    }
  }

  private func appendFinal(_ text: String) {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty, finalSegments.last != normalized else {
      return
    }
    finalSegments.append(normalized)
  }

  private func resolve() {
    guard error == nil, resolvedResult == nil else {
      return
    }
    elevenLabsFinishResolutionTask?.cancel()
    elevenLabsFinishResolutionTask = nil
    let result = result()
    resolvedResult = result
    let pending = continuations.values
    continuations.removeAll()
    for continuation in pending {
      continuation.resume(returning: result)
    }
  }

  private func result() -> TranscriptionResult {
    TranscriptionResult(
      text: doneText ?? joinedText(),
      providerName: providerName,
      duration: duration
    )
  }

  private func joinedText() -> String {
    var segments = finalSegments
    let uncommittedText = mergeIncrementalText(xaiLockedUtterance, latestPartial)
    if !uncommittedText.isEmpty, segments.last != uncommittedText {
      segments.append(uncommittedText)
    }
    return segments.joined(separator: " ")
  }

  /// Keeps the fuller prefix revision, joining only distinct incremental fragments with a space.
  private func mergeIncrementalText(_ existing: String, _ update: String) -> String {
    let existing = existing.trimmingCharacters(in: .whitespacesAndNewlines)
    let update = update.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !existing.isEmpty else {
      return update
    }
    guard !update.isEmpty, update != existing else {
      return existing
    }
    if update.hasPrefix(existing) {
      return update
    }
    if existing.hasPrefix(update) {
      return existing
    }
    return "\(existing) \(update)"
  }

  private func publishCurrentText() {
    let text = joinedText()
    guard !text.isEmpty else {
      return
    }
    onPartialTranscript?(text)
  }

  private func failMessage(_ message: String) {
    fail(
      NSError(
        domain: "Vhrase.Realtime",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: message]
      ))
  }

  private func cancelWaiter(_ id: UUID) {
    continuations.removeValue(forKey: id)?.resume(throwing: CancellationError())
  }

  /// Resolves only after committed and partial traffic has been quiet long enough to drain a final commit.
  private func scheduleElevenLabsFinishResolution() {
    elevenLabsFinishResolutionTask?.cancel()
    let settleNanoseconds = elevenLabsFinishSettleNanoseconds
    elevenLabsFinishResolutionTask = Task { [weak self] in
      do {
        guard let self else {
          return
        }
        try await Task.sleep(nanoseconds: settleNanoseconds)
        try Task.checkCancellation()
        await self.resolveElevenLabsFinish()
      } catch {
        return
      }
    }
  }

  private func resolveElevenLabsFinish() {
    guard isElevenLabsFinishCommitPending else {
      return
    }
    doneText = joinedText()
    resolve()
  }
}

/// Races a terminal transcript against a bounded timeout without stranding the losing waiter.
func waitForRealtimeResult(
  _ accumulator: RealtimeTranscriptAccumulator,
  timeoutNanoseconds: UInt64 = 20_000_000_000
) async throws -> TranscriptionResult {
  try await withThrowingTaskGroup(of: TranscriptionResult.self) { group in
    defer { group.cancelAll() }
    group.addTask {
      try await accumulator.waitForDone()
    }
    group.addTask {
      try await Task.sleep(nanoseconds: timeoutNanoseconds)
      throw NSError(
        domain: "Vhrase.Realtime",
        code: 2,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Realtime transcription timed out waiting for a final transcript."
        ]
      )
    }

    guard let result = try await group.next() else {
      throw NSError(
        domain: "Vhrase.Realtime",
        code: 3,
        userInfo: [NSLocalizedDescriptionKey: "Realtime transcription ended without a result."]
      )
    }
    return result
  }
}
