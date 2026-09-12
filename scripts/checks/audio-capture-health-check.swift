// Exercises missing PCM delivery, error propagation, and cancellable hardware waits without acquiring the microphone.

import Foundation

@main
struct AudioCaptureHealthCheck {
  static func main() async throws {
    let state = AudioCaptureState(startedAt: 100)
    precondition(state.failure(at: 104.9) == nil)
    guard case .audioDeliveryStopped = state.failure(at: 105) as? AudioRecorderError else {
      preconditionFailure("Capture without any PCM must report a stall.")
    }
    for second in 105...120 {
      state.recordChunk(at: Double(second))
      precondition(state.failure(at: Double(second) + 0.9) == nil)
    }
    guard case .audioDeliveryStopped = state.failure(at: 125) as? AudioRecorderError else {
      preconditionFailure("Previously healthy capture must detect stopped delivery.")
    }
    let hardwareError = NSError(domain: "AudioHealthCheck", code: 42)
    state.recordError(hardwareError)
    precondition((state.failure(at: 121) as NSError?) == hardwareError)
    state.recordError(NSError(domain: "LaterError", code: 1))
    precondition((state.firstError as NSError?) == hardwareError)
    state.stopAndWait()
    precondition(state.failure(at: 200) == nil && !state.beginCallback())

    try await verifyHardwareWaits()
    print("audio capture health and hardware cancellation check passed")
  }

  /// Holds a fake hardware queue past cancellation and timeout, proving callers can return before the driver does.
  private static func verifyHardwareWaits() async throws {
    let queue = DispatchQueue(label: "Vhrase.CaptureHealthCheck")
    let blocked = DispatchSemaphore(value: 0)
    let entered = DispatchSemaphore(value: 0)
    defer { blocked.signal() }
    let pending = Task {
      try await DeviceAudioCapture.perform(on: queue, timeoutError: .startupTimedOut) {
        entered.signal()
        blocked.wait()
      }
    }
    // Main is deliberately nonisolated so the task can enter hardware setup while this thread waits.
    precondition(entered.wait(timeout: .now() + 2) == .success)
    pending.cancel()
    do {
      try await pending.value
      preconditionFailure("Cancelling startup must throw.")
    } catch is CancellationError {}

    do {
      try await DeviceAudioCapture.perform(
        on: queue, timeoutError: .shutdownTimedOut, timeout: .milliseconds(30)
      ) {}
      preconditionFailure("A blocked hardware queue must time out.")
    } catch AudioRecorderError.shutdownTimedOut {}

    blocked.signal()
    try await DeviceAudioCapture.perform(on: queue, timeoutError: .startupTimedOut) {}
  }
}
