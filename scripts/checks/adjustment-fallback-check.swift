// Verifies transcript finalization and adjustment fallback behavior.

import Foundation

@main
struct AdjustmentFallbackCheck {
    static func main() async throws {
        try validateEndpointPolicy()

        let raw = try await finalize(
            rawTranscript: "  Custom dictation raw text.  ",
            adjustWithLLM: false
        )
        precondition(raw.text == "Custom dictation raw text.")
        precondition(raw.warning.isEmpty)
        precondition(raw.cleanup == .raw)

        let fallback = try await finalize(
            rawTranscript: "  Custom dictation raw text.  ",
            useLocalFallback: false
        )
        precondition(fallback.text == "Custom dictation raw text.")
        precondition(fallback.warning == "LLM adjustment failed. Used raw transcript.")
        precondition(fallback.cleanup == .raw)

        let localFallback = try await finalize(
            rawTranscript: "  send this to open AI and x AI with eleven labs  ",
            useLocalFallback: true
        )
        precondition(localFallback.text == "Send this to OpenAI and xAI with ElevenLabs.")
        precondition(localFallback.warning == "LLM adjustment failed. Used local cleanup fallback.")
        precondition(localFallback.cleanup == .localFallback)

        let demo = try await finalize(
            rawTranscript: "raw",
            adjustment: .localDemo
        )
        precondition(demo.text == "Please send this custom dictation demo to OpenAI and xAI using ElevenLabs.")
        precondition(demo.warning.isEmpty)
        precondition(demo.cleanup == .demo)

        let screenshotProbe = ScreenshotProbe()
        let preflightFallback = try await finalize(
            rawTranscript: "raw",
            includeScreenshot: true,
            useLocalFallback: false,
            screenshotDataURLProvider: {
                screenshotProbe.recordCall()
                return nil
            }
        )
        precondition(preflightFallback.text == "raw")
        precondition(preflightFallback.warning == "LLM adjustment failed. Used raw transcript.")
        precondition(preflightFallback.cleanup == .raw)
        precondition(!screenshotProbe.wasCalled)

        let chinese = try await finalize(
            rawTranscript: "汉语发布后",
            adjustWithLLM: false,
            chineseTextConverter: ChineseTextConverter(
                executableURL: try fakeOpenCCExecutable(),
                configName: "s2hk.json"
            )
        )
        precondition(chinese.text == "漢語發佈後")
        precondition(chinese.warning.isEmpty)
        precondition(chinese.cleanup == .raw)

        let largeConversion = ChineseTextConverter(
            executableURL: try largeOutputOpenCCExecutable(),
            timeoutSeconds: 2
        )
        .convert("large output")
        precondition(largeConversion.text.count == 100_000)
        precondition(largeConversion.warning == nil)

        let failedConversion = ChineseTextConverter(
            executableURL: try failingOpenCCExecutable()
        )
        .convert("preserve me")
        precondition(failedConversion.text == "preserve me")
        precondition(failedConversion.warning == "OpenCC s2hk failed: conversion exploded")

        let timedOutConversion = ChineseTextConverter(
            executableURL: try slowOpenCCExecutable(),
            timeoutSeconds: 0.1
        )
        .convert("preserve me")
        precondition(timedOutConversion.text == "preserve me")
        precondition(timedOutConversion.warning == "OpenCC s2hk failed: OpenCC timed out after 0.1 seconds.")

        let missingOpenCC = try await finalize(
            rawTranscript: "plain text",
            adjustWithLLM: false,
            chineseTextConverter: ChineseTextConverter(executableURL: nil)
        )
        precondition(missingOpenCC.text == "plain text")
        precondition(missingOpenCC.warning == "OpenCC s2hk unavailable. Final transcript was not normalized.")

        print("adjustment fallback ok")
    }

    /// Protects remote transport and URL composition policy without making a network request.
    private static func validateEndpointPolicy() throws {
        for baseURL in [
            "https://ai-gateway.vercel.sh/v1",
            "https://api.openai.com/v1",
            "https://api.x.ai/v1",
        ] {
            let endpoint = try LLMEndpoint(baseURL: baseURL)
            let modelsURL = try endpoint.appending("models")
            precondition(modelsURL.absoluteString == "\(baseURL)/models")
        }

        let localhost = try LLMEndpoint(baseURL: "http://localhost:11434/v1/")
        let localhostChatURL = try localhost.appending("chat/completions")
        precondition(localhostChatURL.absoluteString == "http://localhost:11434/v1/chat/completions")

        let ipv4Loopback = try LLMEndpoint(baseURL: "http://127.0.0.1:8080")
        let ipv4ModelsURL = try ipv4Loopback.appending("models")
        precondition(ipv4ModelsURL.absoluteString == "http://127.0.0.1:8080/models")

        let ipv6Loopback = try LLMEndpoint(baseURL: "http://[::1]:8080/v1")
        let ipv6ModelsURL = try ipv6Loopback.appending("models")
        precondition(ipv6ModelsURL.absoluteString == "http://[::1]:8080/v1/models")

        for invalidBaseURL in [
            "api.example.com/v1",
            "ftp://api.example.com/v1",
            "http://api.example.com/v1",
            "http://localhost.example.com/v1",
            "https://user:secret@api.example.com/v1",
            "https://api.example.com/v1?token=secret",
            "https://api.example.com/v1#fragment",
            "https://exa_mple.com/v1",
            "https://example..com/v1",
            "https://999.999.999.999/v1",
            "https://api.example.com:/v1",
            "https://api.example.com:0/v1",
            "https://api.example.com:65536/v1",
            "https://[::1]:/v1",
            "https://api.example.com/v1/../models",
            "https://api.example.com/v1%2Fmodels",
            "https://api.example.com//v1",
            "https://%61pi.example.com/v1",
        ] {
            precondition(rejectsBaseURL(invalidBaseURL), "Accepted unsafe LLM base URL: \(invalidBaseURL)")
        }

        let endpoint = try LLMEndpoint(baseURL: "https://api.example.com/v1")
        for invalidPath in [
            "/models",
            "../models",
            "chat//completions",
            "models?owner=other",
            "https://other.example.com/models",
        ] {
            precondition(rejectsPath(invalidPath, from: endpoint), "Accepted unsafe LLM endpoint path: \(invalidPath)")
        }
    }

    private static func rejectsBaseURL(_ value: String) -> Bool {
        do {
            _ = try LLMEndpoint(baseURL: value)
            return false
        } catch {
            return true
        }
    }

    private static func rejectsPath(
        _ path: String,
        from endpoint: LLMEndpoint
    ) -> Bool {
        do {
            _ = try endpoint.appending(path)
            return false
        } catch {
            return true
        }
    }

    private static func finalize(
        rawTranscript: String,
        adjustment: AdjustmentExecution = .provider,
        adjustWithLLM: Bool = true,
        includeScreenshot: Bool = false,
        useLocalFallback: Bool = false,
        chineseTextConverter: ChineseTextConverter? = nil,
        screenshotDataURLProvider: @escaping @Sendable () -> String? = {
            "data:image/png;base64,abc"
        }
    ) async throws -> FinalizedTranscript {
        var settings = DictationSettings.defaults
        settings.adjustWithLLM = adjustWithLLM
        settings.includeScreenshot = includeScreenshot
        settings.useLocalAdjustmentFallback = useLocalFallback
        let converter = try chineseTextConverter ?? ChineseTextConverter(
            executableURL: fakeOpenCCExecutable(),
            configName: "s2hk.json"
        )

        return try await TranscriptFinalizer(
            settings: settings,
            llmAPIKey: "",
            screenshotDataURLProvider: screenshotDataURLProvider,
            chineseTextConverter: converter
        )
        .finalize(
            TranscriptionResult(
                text: rawTranscript,
                providerName: "Test",
                duration: nil
            ),
            adjustment: adjustment,
            targetApp: nil
        )
    }

    private static func fakeOpenCCExecutable() throws -> URL {
        try writeExecutable(
            named: "fake-opencc",
            script: """
            #!/usr/bin/env bash
            /usr/bin/sed -e 's/汉/漢/g' -e 's/语/語/g' -e 's/发/發/g' -e 's/布/佈/g' -e 's/后/後/g'
            """
        )
    }

    private static func largeOutputOpenCCExecutable() throws -> URL {
        try writeExecutable(
            named: "large-output-opencc",
            script: """
            #!/usr/bin/env bash
            /usr/bin/python3 -c 'import sys; sys.stdin.read(); sys.stdout.write("漢" * 100000)'
            """
        )
    }

    private static func failingOpenCCExecutable() throws -> URL {
        try writeExecutable(
            named: "failing-opencc",
            script: """
            #!/usr/bin/env bash
            /bin/cat >/dev/null
            echo 'conversion exploded' >&2
            exit 7
            """
        )
    }

    private static func slowOpenCCExecutable() throws -> URL {
        try writeExecutable(
            named: "slow-opencc",
            script: """
            #!/usr/bin/env bash
            exec /bin/sleep 2
            """
        )
    }

    private static func writeExecutable(
        named name: String,
        script: String
    ) throws -> URL {
        let directory = URL(fileURLWithPath: ".cache/checks", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent(name)
        try script.write(
            to: url,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
        return url
    }
}

private final class ScreenshotProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0

    var wasCalled: Bool {
        lock.withLock { callCount > 0 }
    }

    func recordCall() {
        lock.withLock {
            callCount += 1
        }
    }
}
