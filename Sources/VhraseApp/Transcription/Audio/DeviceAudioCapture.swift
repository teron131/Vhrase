// Captures a specifically selected microphone through AVFoundation without configuring any playback device.

@preconcurrency import AVFoundation
import Foundation
import OSLog

final class DeviceAudioCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate,
  @unchecked Sendable
{
  static let operationTimeoutSeconds = 8

  private let session = AVCaptureSession()
  private let output = AVCaptureAudioDataOutput()
  private let controlQueue = DispatchQueue(label: "Vhrase.DeviceCaptureControl")
  private let sampleQueue = DispatchQueue(label: "Vhrase.DeviceCaptureSamples")
  private let onBuffer: @Sendable (AVAudioPCMBuffer) -> Void
  private let onError: @Sendable (Error) -> Void
  private let logger = Logger(subsystem: "local.codex.Vhrase", category: "DeviceCapture")
  private var observers: [NSObjectProtocol] = []

  var isRunning: Bool { session.isRunning }

  init(
    uid: String, onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
    onError: @escaping @Sendable (Error) -> Void
  ) throws {
    self.onBuffer = onBuffer
    self.onError = onError
    super.init()
    guard let device = AVCaptureDevice(uniqueID: uid) else {
      throw NSError(
        domain: "Vhrase.Audio", code: 2,
        userInfo: [
          NSLocalizedDescriptionKey:
            "The selected microphone is unavailable. Choose another input device."
        ])
    }
    let input = try AVCaptureDeviceInput(device: device)
    session.beginConfiguration()
    defer { session.commitConfiguration() }
    guard session.canAddInput(input), session.canAddOutput(output) else {
      throw NSError(
        domain: "Vhrase.Audio", code: 3,
        userInfo: [
          NSLocalizedDescriptionKey: "This microphone does not support audio capture."
        ])
    }
    session.addInput(input)
    output.audioSettings = PCM16AudioConverter.format.settings
    output.setSampleBufferDelegate(self, queue: sampleQueue)
    session.addOutput(output)
    observers.append(
      NotificationCenter.default.addObserver(
        forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil
      ) { [weak self] notification in
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
        self?.logger.error(
          "Capture runtime error domain=\(error?.domain ?? "unknown", privacy: .public) code=\(error?.code ?? 0)"
        )
        self?.onError(error ?? AudioRecorderError.captureInterrupted)
      })
    observers.append(
      NotificationCenter.default.addObserver(
        forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil
      ) { [weak self] _ in
        self?.logger.error("Capture session interrupted")
        self?.onError(AudioRecorderError.captureInterrupted)
      })
    observers.append(
      NotificationCenter.default.addObserver(
        forName: AVCaptureDevice.wasDisconnectedNotification, object: device, queue: nil
      ) { [weak self] _ in
        self?.logger.error("Selected microphone disconnected")
        self?.onError(AudioRecorderError.captureInterrupted)
      })
  }

  deinit {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }

  /// Bounds the caller's wait while hardware startup stays on its queue; cancellation never waits for the driver.
  func start() async throws {
    logger.notice("Capture start requested")
    try await Self.perform(on: controlQueue, timeoutError: .startupTimedOut) {
      self.session.startRunning()
      self.logger.notice("Capture start returned running=\(self.session.isRunning)")
    }
  }

  /// Preserves samples queued before hardware stop, without holding the main actor while the device drains.
  func stop() async throws {
    logger.notice("Capture stop requested")
    try await Self.perform(on: controlQueue, timeoutError: .shutdownTimedOut) {
      self.stopHardware()
    }
  }

  /// Queues hardware teardown without blocking the main actor; the recorder separately gates and drains PCM callbacks.
  func cancel() {
    logger.notice("Capture stop queued")
    controlQueue.async { self.stopHardware() }
  }

  private func stopHardware() {
    session.stopRunning()
    output.setSampleBufferDelegate(nil, queue: nil)
    sampleQueue.sync {}
    logger.notice("Capture stopped")
  }

  /// Bounds a serial hardware operation without a structured child task that would wait forever for a stuck driver.
  static func perform(
    on queue: DispatchQueue, timeoutError: AudioRecorderError,
    timeout: Duration = .seconds(operationTimeoutSeconds),
    operation: @escaping @Sendable () -> Void
  ) async throws {
    try Task.checkCancellation()
    let (completion, continuation) = AsyncThrowingStream<Never, Error>.makeStream()
    let deadline = Task {
      do { try await Task.sleep(for: timeout) } catch { return }
      continuation.finish(throwing: timeoutError)
    }
    defer { deadline.cancel() }
    queue.async {
      operation()
      continuation.finish()
    }
    for try await _ in completion {}
    try Task.checkCancellation()
  }

  func captureOutput(
    _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    let frames = CMSampleBufferGetNumSamples(sampleBuffer)
    guard frames > 0,
      let buffer = AVAudioPCMBuffer(
        pcmFormat: PCM16AudioConverter.format,
        frameCapacity: AVAudioFrameCount(frames))
    else { return }
    buffer.frameLength = AVAudioFrameCount(frames)
    let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
      sampleBuffer, at: 0,
      frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
    guard status == noErr else {
      onError(NSError(domain: NSOSStatusErrorDomain, code: Int(status)))
      return
    }
    onBuffer(buffer)
  }
}
