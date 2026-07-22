// Records temporary microphone audio and emits normalized realtime PCM chunks for transcription.

@preconcurrency import AVFoundation
import Foundation

struct AudioChunk: Sendable {
    let data: Data
    let level: Double
}

typealias AudioChunkHandler = @Sendable (AudioChunk) -> Void

/// Records microphone audio while keeping CoreAudio tap work off the main actor.
@MainActor
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var outputURL: URL?
    private var realtimeConverter: PCM16AudioConverter?
    private var audioChunkHandler: AudioChunkHandler?
    private var captureState: AudioCaptureState?

    var isRecording: Bool {
        engine.isRunning
    }

    /// Starts microphone capture and optionally emits normalized realtime chunks.
    func start(onAudioChunk: AudioChunkHandler? = nil) async throws {
        try Task.checkCancellation()
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        try Task.checkCancellation()
        guard granted else {
            throw NSError(
                domain: "Vhrase.Audio",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Microphone access was not granted."]
            )
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let url = try nextRecordingURL()
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let converter = onAudioChunk.map { _ in PCM16AudioConverter(inputFormat: format) }
        let captureState = AudioCaptureState()
        let tapProcessor = AudioTapProcessor(
            file: file,
            converter: converter,
            chunkHandler: onAudioChunk,
            captureState: captureState
        )

        do {
            input.removeTap(onBus: 0)
            input.installTap(
                onBus: 0,
                bufferSize: 4_096,
                format: format,
                block: Self.makeAudioTapBlock { buffer in
                    tapProcessor.process(buffer)
                }
            )

            audioFile = file
            outputURL = url
            realtimeConverter = converter
            audioChunkHandler = onAudioChunk
            self.captureState = captureState
            engine.prepare()
            try engine.start()
            try Task.checkCancellation()
        } catch {
            input.removeTap(onBus: 0)
            engine.stop()
            captureState.stopAndWait()
            audioFile = nil
            outputURL = nil
            realtimeConverter = nil
            audioChunkHandler = nil
            self.captureState = nil
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    /// Creates a CoreAudio callback without inheriting the recorder's main-actor isolation.
    nonisolated static func makeAudioTapBlock(
        process: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            process(buffer)
        }
    }

    /// Stops capture, flushes one silence-padded final realtime chunk, and returns the recorded file.
    func stop() throws -> URL {
        guard let outputURL else {
            throw AudioRecorderError.noActiveRecording
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        captureState?.stopAndWait()
        let recordedFrameCount = audioFile?.length ?? 0
        let writeError = captureState?.firstWriteError
        let converter = realtimeConverter
        let chunkHandler = audioChunkHandler
        audioFile = nil
        realtimeConverter = nil
        audioChunkHandler = nil
        captureState = nil
        self.outputURL = nil

        if let writeError {
            try? FileManager.default.removeItem(at: outputURL)
            throw AudioRecorderError.fileWriteFailed(writeError)
        }
        guard recordedFrameCount > 0 else {
            try? FileManager.default.removeItem(at: outputURL)
            throw AudioRecorderError.emptyRecording
        }
        for finalChunk in converter?.finish() ?? [] {
            chunkHandler?(finalChunk)
        }
        return outputURL
    }

    /// Stops capture without producing a transcript and deletes the temporary recording.
    func cancel() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        captureState?.stopAndWait()
        audioFile = nil
        realtimeConverter = nil
        audioChunkHandler = nil
        captureState = nil
        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        outputURL = nil
    }

    /// Best-effort removes recordings abandoned by a previous app lifetime without creating the directory.
    static func removeAbandonedRecordings() {
        guard let directory = try? recordingsDirectory(createIfNeeded: false),
              let files = try? FileManager.default.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: [.isRegularFileKey],
                  options: [.skipsHiddenFiles]
              ) else {
            return
        }

        for file in files where file.pathExtension.lowercased() == "wav"
            && file.lastPathComponent.hasPrefix("recording-") {
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else {
                continue
            }
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func nextRecordingURL() throws -> URL {
        let directory = try Self.recordingsDirectory(createIfNeeded: true)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let name = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")

        return directory.appendingPathComponent("recording-\(name).wav")
    }

    private static func recordingsDirectory(createIfNeeded: Bool) throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: createIfNeeded
        )
        let directory = base.appendingPathComponent("Vhrase/Recordings", isDirectory: true)
        if createIfNeeded {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }
}

enum AudioRecorderError: LocalizedError {
    case noActiveRecording
    case fileWriteFailed(Error)
    case emptyRecording

    var errorDescription: String? {
        switch self {
        case .noActiveRecording:
            "There is no active recording."
        case .fileWriteFailed(let error):
            "Vhrase could not save the recording: \(error.localizedDescription)"
        case .emptyRecording:
            "The recording contained no audio."
        }
    }
}

private final class AudioCaptureState: @unchecked Sendable {
    private let condition = NSCondition()
    private var activeCallbacks = 0
    private var isStopping = false
    private var writeError: Error?

    var firstWriteError: Error? {
        condition.withLock { writeError }
    }

    func beginCallback() -> Bool {
        condition.withLock {
            guard !isStopping else {
                return false
            }
            activeCallbacks += 1
            return true
        }
    }

    func endCallback() {
        condition.withLock {
            activeCallbacks -= 1
            if activeCallbacks == 0 {
                condition.broadcast()
            }
        }
    }

    func recordWriteError(_ error: Error) {
        condition.withLock {
            if writeError == nil {
                writeError = error
            }
        }
    }

    func stopAndWait() {
        condition.lock()
        isStopping = true
        while activeCallbacks > 0 {
            condition.wait()
        }
        condition.unlock()
    }
}

/// Owns the nonisolated work performed by CoreAudio's realtime callback queue.
private final class AudioTapProcessor: @unchecked Sendable {
    private let file: AVAudioFile
    private let converter: PCM16AudioConverter?
    private let chunkHandler: AudioChunkHandler?
    private let captureState: AudioCaptureState

    init(
        file: AVAudioFile,
        converter: PCM16AudioConverter?,
        chunkHandler: AudioChunkHandler?,
        captureState: AudioCaptureState
    ) {
        self.file = file
        self.converter = converter
        self.chunkHandler = chunkHandler
        self.captureState = captureState
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        guard captureState.beginCallback() else {
            return
        }
        defer {
            captureState.endCallback()
        }
        do {
            try file.write(from: buffer)
        } catch {
            captureState.recordWriteError(error)
            NSLog("Vhrase audio write failed: \(error.localizedDescription)")
        }
        if let chunkHandler, let converter {
            for chunk in converter.convert(buffer) {
                chunkHandler(chunk)
            }
        }
    }
}

final class PCM16AudioConverter: @unchecked Sendable {
    private let converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat?
    private let lock = NSLock()
    private var chunkFramer = PCM16ChunkFramer()

    init(inputFormat: AVAudioFormat) {
        outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        )
        if let outputFormat {
            converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        } else {
            converter = nil
        }
    }

    /// Converts one tap buffer and emits only complete 100 ms PCM16 frames.
    func convert(_ buffer: AVAudioPCMBuffer) -> [AudioChunk] {
        lock.withLock {
            guard let converter, let outputFormat else {
                return []
            }

            let ratio = outputFormat.sampleRate / buffer.format.sampleRate
            let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 512
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
                return []
            }

            var error: NSError?
            let inputProvider = ConverterInputProvider(buffer: buffer)
            let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                inputProvider.next(outStatus)
            }

            guard error == nil, status != .error, outputBuffer.frameLength > 0,
                  let channelData = outputBuffer.int16ChannelData else {
                return []
            }

            let data = Data(
                bytes: channelData[0],
                count: Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size
            )
            return chunkFramer.append(data).map(Self.audioChunk)
        }
    }

    /// Drains sample-rate conversion and pads only the final sub-100 ms remainder with PCM silence.
    func finish() -> [AudioChunk] {
        lock.withLock {
            var chunks: [Data] = []
            if let converter, let outputFormat,
               let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 3_200) {
                var error: NSError?
                let status = converter.convert(to: outputBuffer, error: &error) { _, inputStatus in
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                if error == nil, status != .error, outputBuffer.frameLength > 0,
                   let channelData = outputBuffer.int16ChannelData {
                    let data = Data(
                        bytes: channelData[0],
                        count: Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size
                    )
                    chunks += chunkFramer.append(data)
                }
            }
            if let finalChunk = chunkFramer.finish() {
                chunks.append(finalChunk)
            }
            return chunks.map(Self.audioChunk)
        }
    }

    private static func audioChunk(data: Data) -> AudioChunk {
        AudioChunk(data: data, level: level(from: data))
    }

    private static func level(from data: Data) -> Double {
        guard data.count >= MemoryLayout<Int16>.size else {
            return 0
        }

        let sum = data.withUnsafeBytes { bytes -> Double in
            var sum: Double = 0
            for offset in stride(from: 0, to: data.count, by: MemoryLayout<Int16>.size) {
                let sample = bytes.loadUnaligned(fromByteOffset: offset, as: Int16.self).littleEndian
                let normalized = Double(sample) / Double(Int16.max)
                sum += normalized * normalized
            }
            return sum
        }

        let sampleCount = data.count / MemoryLayout<Int16>.size
        let rms = sqrt(sum / Double(sampleCount))
        return min(1, max(0, rms * 6))
    }
}

/// Buffers normalized mono PCM16 into the 3,200-byte frames expected by realtime providers.
struct PCM16ChunkFramer {
    static let chunkByteCount = 3_200

    private var remainder = Data()

    var remainderByteCount: Int {
        remainder.count
    }

    mutating func append(_ data: Data) -> [Data] {
        guard !data.isEmpty else {
            return []
        }
        remainder.append(data)

        var chunks: [Data] = []
        while remainder.count >= Self.chunkByteCount {
            chunks.append(Data(remainder.prefix(Self.chunkByteCount)))
            remainder.removeFirst(Self.chunkByteCount)
        }
        return chunks
    }

    mutating func finish() -> Data? {
        guard !remainder.isEmpty else {
            return nil
        }

        var finalChunk = remainder
        remainder.removeAll()
        finalChunk.append(Data(
            repeating: 0,
            count: Self.chunkByteCount - finalChunk.count
        ))
        return finalChunk
    }
}

private final class ConverterInputProvider: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard let buffer else {
            status.pointee = .noDataNow
            return nil
        }

        self.buffer = nil
        status.pointee = .haveData
        return buffer
    }
}
