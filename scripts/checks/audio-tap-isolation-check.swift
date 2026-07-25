// Verifies CoreAudio tap work can execute away from the main actor without a Swift executor trap.

@preconcurrency import AVFoundation
import Foundation

private final class TapBlockBox: @unchecked Sendable {
  let block: AVAudioNodeTapBlock

  init(_ block: @escaping AVAudioNodeTapBlock) {
    self.block = block
  }
}

@main
struct AudioTapIsolationCheck {
  static func main() {
    let callbackCompleted = DispatchSemaphore(value: 0)
    let tapBlock = AudioRecorder.makeAudioTapBlock { _ in
      callbackCompleted.signal()
    }
    let tapBlockBox = TapBlockBox(tapBlock)

    DispatchQueue(label: "Vhrase.AudioTapIsolationCheck").async {
      guard
        let format = AVAudioFormat(
          commonFormat: .pcmFormatFloat32,
          sampleRate: 16_000,
          channels: 1,
          interleaved: false
        ), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16)
      else {
        return
      }
      tapBlockBox.block(buffer, AVAudioTime(sampleTime: 0, atRate: 16_000))
    }

    precondition(
      callbackCompleted.wait(timeout: .now() + 2) == .success,
      "CoreAudio tap block did not execute on its callback queue."
    )
    print("audio tap isolation check passed")
  }
}
