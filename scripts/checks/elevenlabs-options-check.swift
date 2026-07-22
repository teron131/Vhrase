// Verifies ElevenLabs request options and realtime transcript terminal-state behavior.

import Foundation

@main
struct ElevenLabsOptionsCheck {
    static func main() async throws {
        var settings = DictationSettings.defaults
        settings.provider = .elevenLabs
        settings.elevenLabsCommitStrategy = .vad
        settings.elevenLabsNoVerbatim = true
        settings.elevenLabsVADSilenceThreshold = 1.2
        settings.elevenLabsVADThreshold = 0.55
        settings.elevenLabsMinSpeechDuration = 150
        settings.elevenLabsMinSilenceDuration = 200
        settings.keyterms = "OpenAI\nElevenLabs"

        let uploadFields = try ElevenLabsTranscriptionContract.uploadFields(settings: settings)
        precondition(uploadFields.contains { $0 == ("model_id", "scribe_v2") })
        precondition(uploadFields.contains { $0 == ("no_verbatim", "true") })
        precondition(uploadFields.filter { $0.0 == "keyterms" }.count == 2)

        let queryItems = try ElevenLabsTranscriptionContract.realtimeQueryItems(settings: settings)
        precondition(value("model_id", in: queryItems) == "scribe_v2_realtime")
        precondition(value("commit_strategy", in: queryItems) == "vad")
        precondition(value("no_verbatim", in: queryItems) == "true")
        precondition(value("vad_silence_threshold_secs", in: queryItems) == "1.2")
        precondition(value("vad_threshold", in: queryItems) == "0.55")
        precondition(value("min_speech_duration_ms", in: queryItems) == "150")
        precondition(value("min_silence_duration_ms", in: queryItems) == "200")
        precondition(queryItems.filter { $0.name == "keyterms" }.count == 2)

        settings.language = " \n "
        let automaticLanguageFields = try ElevenLabsTranscriptionContract.uploadFields(settings: settings)
        precondition(
            !automaticLanguageFields.contains { $0.0 == "language_code" }
        )
        let automaticLanguageQueryItems = try ElevenLabsTranscriptionContract.realtimeQueryItems(settings: settings)
        precondition(value(
            "language_code",
            in: automaticLanguageQueryItems
        ) == nil)

        try verifyKeytermValidation()
        await verifyMultipleCommittedSegments()
        await verifyDocumentedErrors()
        await verifyTimeoutAndCancellation()

        print("ElevenLabs options and realtime state ok")
    }

    private static func verifyKeytermValidation() throws {
        var settings = DictationSettings.defaults
        settings.provider = .elevenLabs
        settings.transcriptionMode = .upload
        settings.keyterms = Array(repeating: "valid", count: 1_000).joined(separator: "\n")
        try TranscriptionContract.validate(settings: settings)
        settings.keyterms += "\none too many"
        expectValidationFailure(settings, containing: "at most 1000 keyterms")

        settings.keyterms = String(repeating: "x", count: 49)
        try TranscriptionContract.validate(settings: settings)
        settings.keyterms += "x"
        expectValidationFailure(settings, containing: "fewer than 50 characters")

        settings.keyterms = "one two three four five"
        try TranscriptionContract.validate(settings: settings)
        settings.keyterms += " six"
        expectValidationFailure(settings, containing: "at most 5 words")

        for character in ["<", ">", "{", "}", "[", "]", "\\"] {
            settings.keyterms = "invalid\(character)term"
            expectValidationFailure(settings, containing: "unsupported character")
        }

        settings.transcriptionMode = .realtime
        settings.keyterms = Array(repeating: "valid", count: 50).joined(separator: "\n")
        try TranscriptionContract.validate(settings: settings)
        settings.keyterms += "\none too many"
        expectValidationFailure(settings, containing: "at most 50 keyterms")

        settings.keyterms = String(repeating: "x", count: 20)
        try TranscriptionContract.validate(settings: settings)
        settings.keyterms += "x"
        expectValidationFailure(settings, containing: "at most 20 characters")
    }

    private static func expectValidationFailure(
        _ settings: DictationSettings,
        containing expectedMessage: String
    ) {
        do {
            try TranscriptionContract.validate(settings: settings)
            preconditionFailure("Invalid ElevenLabs keyterms passed validation")
        } catch {
            precondition(error.localizedDescription.contains(expectedMessage))
        }
    }

    private static func verifyMultipleCommittedSegments() async {
        let capture = LockedTranscriptCapture()
        let accumulator = RealtimeTranscriptAccumulator(
            providerName: "ElevenLabs Realtime",
            onPartialTranscript: { @Sendable text in
                capture.record(text)
            },
            elevenLabsFinishSettleNanoseconds: 30_000_000
        )
        let firstCommitOutcome = await accumulator.handleElevenLabs(
            ElevenLabsRealtimeEvent(
                message_type: "committed_transcript",
                text: "First segment"
            )
        )
        guard case .continueReceiving = firstCommitOutcome else {
            preconditionFailure("The first automatic commit was terminal")
        }

        let outcome = await firstWaitOutcome(accumulator)
        guard case .timedOut = outcome else {
            preconditionFailure("A committed segment completed the session before finish was requested: \(outcome)")
        }

        let secondCommitOutcome = await accumulator.handleElevenLabs(
            ElevenLabsRealtimeEvent(
                message_type: "committed_transcript_with_timestamps",
                text: "Second segment"
            )
        )
        guard case .continueReceiving = secondCommitOutcome else {
            preconditionFailure("The second automatic commit was terminal")
        }

        _ = await accumulator.handleElevenLabs(
            ElevenLabsRealtimeEvent(
                message_type: "partial_transcript",
                text: "Third draft"
            )
        )
        precondition(capture.latest == "First segment Second segment Third draft")

        await accumulator.beginElevenLabsFinishCommit()
        let delayedAutomaticCommitOutcome = await accumulator.handleElevenLabs(
            ElevenLabsRealtimeEvent(
                message_type: "committed_transcript",
                text: "Third segment"
            )
        )
        guard case .continueReceiving = delayedAutomaticCommitOutcome else {
            preconditionFailure("A delayed automatic commit ended the final drain")
        }
        let drainOutcome = await firstWaitOutcome(
            accumulator,
            timeoutNanoseconds: 10_000_000
        )
        guard case .timedOut = drainOutcome else {
            preconditionFailure("The delayed automatic commit resolved before the drain: \(drainOutcome)")
        }

        _ = await accumulator.handleElevenLabs(
            ElevenLabsRealtimeEvent(
                message_type: "partial_transcript",
                text: "Fourth draft"
            )
        )
        let finalCommitOutcome = await accumulator.handleElevenLabs(
            ElevenLabsRealtimeEvent(
                message_type: "committed_transcript",
                text: "Fourth segment"
            )
        )
        guard case .continueReceiving = finalCommitOutcome else {
            preconditionFailure("The explicit final commit bypassed the final drain")
        }
        do {
            let result = try await accumulator.waitForDone()
            precondition(result.text == "First segment Second segment Third segment Fourth segment")
        } catch {
            preconditionFailure("Final ElevenLabs commit failed: \(error.localizedDescription)")
        }
    }

    private static func verifyDocumentedErrors() async {
        let messageTypes = [
            "auth_error",
            "chunk_size_exceeded",
            "commit_throttled",
            "error",
            "input_error",
            "insufficient_audio_activity",
            "queue_overflow",
            "quota_exceeded",
            "rate_limited",
            "resource_exhausted",
            "session_time_limit_exceeded",
            "transcriber_error",
            "unaccepted_terms",
        ]

        for messageType in messageTypes {
            let accumulator = RealtimeTranscriptAccumulator(
                providerName: "ElevenLabs Realtime",
                onPartialTranscript: nil
            )
            let outcome = await accumulator.handleElevenLabs(
                ElevenLabsRealtimeEvent(
                    message_type: messageType,
                    error: "provider detail"
                )
            )
            guard case .failed = outcome else {
                preconditionFailure("ElevenLabs error event was not terminal: \(messageType)")
            }
            do {
                _ = try await accumulator.waitForDone()
                preconditionFailure("ElevenLabs error event returned a transcript: \(messageType)")
            } catch {
                precondition(error.localizedDescription.contains(messageType))
                precondition(error.localizedDescription.contains("provider detail"))
            }
        }
    }

    private static func verifyTimeoutAndCancellation() async {
        let timeoutAccumulator = RealtimeTranscriptAccumulator(
            providerName: "ElevenLabs Realtime",
            onPartialTranscript: nil
        )
        do {
            _ = try await waitForRealtimeResult(
                timeoutAccumulator,
                timeoutNanoseconds: 20_000_000
            )
            preconditionFailure("Realtime wait returned without a terminal event")
        } catch {
            precondition(error.localizedDescription.contains("timed out"))
        }

        let cancellationAccumulator = RealtimeTranscriptAccumulator(
            providerName: "ElevenLabs Realtime",
            onPartialTranscript: nil
        )
        let waitTask = Task {
            try await cancellationAccumulator.waitForDone()
        }
        await Task.yield()
        waitTask.cancel()
        do {
            _ = try await waitTask.value
            preconditionFailure("Cancelled realtime wait returned a transcript")
        } catch {
            precondition(error is CancellationError)
        }
    }

    private static func firstWaitOutcome(
        _ accumulator: RealtimeTranscriptAccumulator,
        timeoutNanoseconds: UInt64 = 20_000_000
    ) async -> WaitOutcome {
        await withTaskGroup(of: WaitOutcome.self) { group in
            group.addTask {
                do {
                    let result = try await accumulator.waitForDone()
                    return .completed(result.text)
                } catch {
                    return .failed(error.localizedDescription)
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return .timedOut
            }

            let outcome = await group.next() ?? .failed("No wait outcome")
            group.cancelAll()
            return outcome
        }
    }

    private static func value(
        _ name: String,
        in queryItems: [URLQueryItem]
    ) -> String? {
        queryItems.first { $0.name == name }?.value
    }
}

private final class LockedTranscriptCapture: @unchecked Sendable {
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

private enum WaitOutcome: CustomStringConvertible, Sendable {
    case completed(String)
    case failed(String)
    case timedOut

    var description: String {
        switch self {
        case .completed(let text):
            "completed(\(text))"
        case .failed(let message):
            "failed(\(message))"
        case .timedOut:
            "timedOut"
        }
    }
}
