// Verifies preview cancellation invalidates delayed microphone startup without requesting microphone access.

import AVFoundation
import Foundation

@main
struct AudioPreviewCheck {
  @MainActor
  static func main() async throws {
    try verifyClip()
    let preview = AudioInputPreview()
    preview.start(settings: .defaults)
    precondition(preview.isStarting)
    preview.stop()
    precondition(!preview.isStarting && !preview.isListening && preview.level == 0)
    try await Task.sleep(for: .milliseconds(250))
    precondition(!preview.isListening && preview.errorMessage.isEmpty)

    // Replacing a pending configuration and immediately starting dictation must cancel both startups.
    preview.start(settings: .defaults)
    var settings = DictationSettings.defaults
    settings.inputGainDB = 3
    preview.restart(settings: settings)
    preview.stop()
    try await Task.sleep(for: .milliseconds(250))
    precondition(!preview.isStarting && !preview.isListening && preview.errorMessage.isEmpty)
    print("audio preview cancellation check passed")
  }

  private static func verifyClip() throws {
    var clip = AudioTestClip()
    precondition(clip.isEmpty)
    for _ in 0..<55 { clip.append(Data(repeating: 0, count: 3_200)) }
    precondition(clip.isComplete && clip.pcm.count == 160_000)
    let player = try AVAudioPlayer(data: clip.wavData)
    precondition(abs(player.duration - 5) < 0.001)
    precondition(player.numberOfChannels == 1)
    precondition(player.format.sampleRate == 16_000)
  }
}
