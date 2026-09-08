// Captures a specifically selected microphone through AVFoundation without configuring any playback device.

@preconcurrency import AVFoundation
import Foundation

final class DeviceAudioCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate,
  @unchecked Sendable
{
  private let session = AVCaptureSession()
  private let output = AVCaptureAudioDataOutput()
  private let controlQueue = DispatchQueue(label: "Vhrase.DeviceCaptureControl")
  private let sampleQueue = DispatchQueue(label: "Vhrase.DeviceCaptureSamples")
  private let onBuffer: @Sendable (AVAudioPCMBuffer) -> Void
  private let onError: @Sendable (Error) -> Void

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
  }

  /// Starts the device on its control queue so hardware setup does not block the settings UI.
  func start() async {
    await withCheckedContinuation { continuation in
      controlQueue.async {
        self.session.startRunning()
        continuation.resume()
      }
    }
  }

  /// Waits for setup and queued sample delivery before the recorder flushes or discards its processor.
  func stop() {
    controlQueue.sync { session.stopRunning() }
    output.setSampleBufferDelegate(nil, queue: nil)
    sampleQueue.sync {}
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
