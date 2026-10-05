// Verifies xAI request options and all documented realtime partial-final states.

@preconcurrency import AVFoundation
import Foundation

@main
struct XAISTTOptionsCheck {
  static func main() async throws {
    var settings = DictationSettings.defaults
    settings.language = "en"
    settings.includeFillerWords = false
    settings.xaiRealtimeEndpointing = 700
    settings.xaiSmartTurnEnabled = true
    settings.xaiSmartTurnThreshold = 0.65
    settings.xaiSmartTurnTimeout = 1800
    settings.keyterms = "OpenAI\nElevenLabs"

    let uploadFields = try XAITranscriptionContract.uploadFields(settings: settings)
    precondition(uploadFields.contains { $0 == ("format", "true") })
    precondition(uploadFields.contains { $0 == ("language", "en") })
    precondition(!uploadFields.contains { $0.0 == "diarize" })
    precondition(uploadFields.filter { $0.0 == "keyterm" }.count == 2)

    settings.language = "  \n"
    let automaticLanguageFields = try XAITranscriptionContract.uploadFields(settings: settings)
    precondition(!automaticLanguageFields.contains { $0.0 == "format" })
    precondition(!automaticLanguageFields.contains { $0.0 == "language" })

    let queryItems = try XAITranscriptionContract.realtimeQueryItems(settings: settings)
    precondition(value("diarize", in: queryItems) == nil)
    precondition(value("endpointing", in: queryItems) == "700")
    precondition(value("smart_turn", in: queryItems) == "0.65")
    precondition(value("smart_turn_timeout", in: queryItems) == "1800")
    precondition(queryItems.filter { $0.name == "keyterm" }.count == 2)
    precondition(value("language", in: queryItems) == nil)

    try verifyKeytermValidation()
    try verifyPreReadyAudioQueue()
    verifyPCMFraming()
    verifyPCMConversion()
    await verifyRealtimeFinalStates()
    await verifyEmptyDoneFallsBackToPartial()

    print("xAI STT option shape ok")
  }

  private static func verifyKeytermValidation() throws {
    var settings = DictationSettings.defaults
    settings.provider = .xai
    settings.transcriptionMode = .upload
    settings.keyterms = (1...100).map { "term \($0)" }.joined(separator: "\n")
    try TranscriptionContract.validate(settings: settings)

    settings.keyterms += "\none too many"
    expectValidationFailure(settings, containing: "at most 100 keyterms")

    settings.transcriptionMode = .realtime
    settings.keyterms = String(repeating: "x", count: 50)
    try TranscriptionContract.validate(settings: settings)
    settings.keyterms += "x"
    expectValidationFailure(settings, containing: "at most 50 characters")
  }

  private static func verifyPreReadyAudioQueue() throws {
    var queue = PreReadyAudioQueue()
    let leading = Data(repeating: 1, count: PreReadyAudioQueue.maximumBufferedByteCount - 3_200)
    let trailing = Data(repeating: 2, count: 3_200)
    try queue.append(leading, providerName: "Test Realtime")
    try queue.append(trailing, providerName: "Test Realtime")
    precondition(queue.byteCount == PreReadyAudioQueue.maximumBufferedByteCount)

    do {
      try queue.append(Data([3]), providerName: "Test Realtime")
      preconditionFailure("The pre-ready queue exceeded its audio cap")
    } catch {
      precondition(error.localizedDescription.contains("15 seconds"))
      precondition(error.localizedDescription.contains("Test Realtime"))
    }

    let drained = queue.drain()
    precondition(drained == [leading, trailing])
    precondition(queue.byteCount == 0)
  }

  private static func verifyPCMFraming() {
    var framer = PCM16ChunkFramer()
    precondition(framer.append(Data(repeating: 1, count: 1_000)).isEmpty)
    let chunks = framer.append(Data(repeating: 2, count: 3_000))
    precondition(chunks.count == 1)
    precondition(chunks[0].count == PCM16ChunkFramer.chunkByteCount)
    precondition(chunks[0].prefix(1_000) == Data(repeating: 1, count: 1_000))
    precondition(chunks[0].suffix(2_200) == Data(repeating: 2, count: 2_200))
    precondition(framer.remainderByteCount == 800)

    let finalChunk = framer.finish()
    precondition(finalChunk?.count == PCM16ChunkFramer.chunkByteCount)
    precondition(finalChunk?.prefix(800) == Data(repeating: 2, count: 800))
    precondition(finalChunk?.suffix(2_400) == Data(repeating: 0, count: 2_400))
    precondition(framer.remainderByteCount == 0)
    precondition(framer.finish() == nil)

    var exactFramer = PCM16ChunkFramer()
    precondition(exactFramer.append(Data(repeating: 4, count: 3_200)).count == 1)
    precondition(exactFramer.finish() == nil)
  }

  private static func verifyPCMConversion() {
    guard
      let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48_000,
        channels: 1,
        interleaved: false
      ), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800),
      let samples = buffer.floatChannelData?[0]
    else {
      preconditionFailure("Could not create the PCM conversion fixture")
    }
    buffer.frameLength = 4_800
    for index in 0..<Int(buffer.frameLength) {
      samples[index] = 0.25
    }

    let converter = PCM16AudioConverter(inputFormat: format)
    let chunks = converter.convert(buffer) + converter.finish()
    precondition(!chunks.isEmpty)
    precondition(chunks.allSatisfy { $0.data.count == PCM16ChunkFramer.chunkByteCount })
    precondition(chunks.contains { $0.level > 0 })
  }

  private static func expectValidationFailure(
    _ settings: DictationSettings,
    containing expectedMessage: String
  ) {
    do {
      try TranscriptionContract.validate(settings: settings)
      preconditionFailure("Invalid xAI keyterms passed validation")
    } catch {
      precondition(error.localizedDescription.contains(expectedMessage))
    }
  }

  private static func verifyRealtimeFinalStates() async {
    let capture = LockedTextCapture()
    let accumulator = RealtimeTranscriptAccumulator(
      providerName: "xAI Realtime",
      onPartialTranscript: { text in
        capture.record(text)
      }
    )
    _ = await accumulator.handleXAI(
      XAIRealtimeEvent(
        type: "transcript.partial",
        text: "draft",
        isFinal: false,
        speechFinal: false,
        message: nil
      ))
    _ = await accumulator.handleXAI(
      XAIRealtimeEvent(
        type: "transcript.partial",
        text: "First locked",
        isFinal: true,
        speechFinal: false,
        message: nil
      ))
    _ = await accumulator.handleXAI(
      XAIRealtimeEvent(
        type: "transcript.partial",
        text: "and drafting",
        isFinal: false,
        speechFinal: false,
        message: nil
      ))
    precondition(capture.latest == "First locked and drafting")
    // Partial and locked updates share prefix semantics, including repeated and shorter revisions.
    for isFinal in [false, true] {
      for (text, expected) in [
        (" First locked ", "First locked"),
        (" First ", "First locked"),
        (" \n ", "First locked"),
      ] {
        _ = await accumulator.handleXAI(
          XAIRealtimeEvent(
            type: "transcript.partial",
            text: text,
            isFinal: isFinal,
            speechFinal: false,
            message: nil
          ))
        precondition(capture.latest == expected)
      }
    }
    _ = await accumulator.handleXAI(
      XAIRealtimeEvent(
        type: "transcript.partial",
        text: "First locked and extended",
        isFinal: true,
        speechFinal: false,
        message: nil
      ))
    _ = await accumulator.handleXAI(
      XAIRealtimeEvent(
        type: "transcript.partial",
        text: "First locked and extended",
        isFinal: true,
        speechFinal: true,
        message: nil
      ))
    _ = await accumulator.handleXAI(
      XAIRealtimeEvent(
        type: "transcript.partial",
        text: "Second final",
        isFinal: true,
        speechFinal: true,
        message: nil
      ))
    precondition(capture.latest == "First locked and extended Second final")
    _ = await accumulator.handleXAI(
      XAIRealtimeEvent(
        type: "transcript.done",
        text: "Authoritative full transcript",
        isFinal: nil,
        speechFinal: nil,
        message: nil
      ))
    do {
      let result = try await accumulator.waitForDone()
      precondition(result.text == "Authoritative full transcript")
    } catch {
      preconditionFailure("xAI accumulator failed: \(error.localizedDescription)")
    }
  }

  /// Replays xAI's observed empty terminal payload after a valid speech-final partial.
  private static func verifyEmptyDoneFallsBackToPartial() async {
    let accumulator = RealtimeTranscriptAccumulator(
      providerName: "xAI Realtime",
      onPartialTranscript: nil
    )
    _ = await accumulator.handleXAI(
      XAIRealtimeEvent(
        type: "transcript.partial",
        text: "Realtime text must survive finalization.",
        isFinal: true,
        speechFinal: true,
        message: nil
      ))
    _ = await accumulator.handleXAI(
      XAIRealtimeEvent(
        type: "transcript.done",
        text: "",
        isFinal: nil,
        speechFinal: nil,
        message: nil
      ))
    do {
      let result = try await accumulator.waitForDone()
      precondition(result.text == "Realtime text must survive finalization.")
    } catch {
      preconditionFailure("Empty xAI terminal payload failed: \(error.localizedDescription)")
    }
  }

  private static func value(
    _ name: String,
    in queryItems: [URLQueryItem]
  ) -> String? {
    queryItems.first { $0.name == name }?.value
  }
}

private final class LockedTextCapture: @unchecked Sendable {
  private let lock = NSLock()
  private var text = ""

  var latest: String {
    lock.withLock { text }
  }

  func record(_ text: String) {
    lock.withLock {
      self.text = text
    }
  }
}
