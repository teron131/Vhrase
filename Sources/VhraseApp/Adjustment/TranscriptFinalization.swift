// Finalizes provider transcripts through replacement, conversion, adjustment, and validation policy.

import Foundation

/// Prepares final transcript text before AppState records history, insertion, and published UI state.
@MainActor
struct TranscriptFinalizer {
  let settings: DictationSettings
  let llmAPIKey: String
  let screenshotDataURLProvider: @Sendable () -> String?
  let replacementProcessor: TextReplacementProcessor
  let chineseTextConverter: ChineseTextConverter

  init(
    settings: DictationSettings,
    llmAPIKey: String,
    screenshotDataURLProvider: @escaping @Sendable () -> String? = {
      ScreenContext().mainDisplayPNGDataURL()
    },
    replacementProcessor: TextReplacementProcessor = TextReplacementProcessor(),
    chineseTextConverter: ChineseTextConverter = ChineseTextConverter()
  ) {
    self.settings = settings
    self.llmAPIKey = llmAPIKey
    self.screenshotDataURLProvider = screenshotDataURLProvider
    self.replacementProcessor = replacementProcessor
    self.chineseTextConverter = chineseTextConverter
  }

  func finalize(
    _ result: TranscriptionResult,
    adjustment: AdjustmentExecution,
    targetApp: FrontmostApp?
  ) async throws -> FinalizedTranscript {
    var finalText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    var warnings: [String] = []

    finalText =
      replacementProcessor
      .apply(settings.replacements, to: finalText)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    try validateTranscript(finalText)

    var cleanup: TranscriptCleanup = .raw

    if settings.adjustWithLLM {
      switch adjustment {
      case .provider:
        do {
          let client = LLMAdjustmentClient(
            apiKey: llmAPIKey,
            baseURL: settings.adjustmentBaseURL
          )
          try client.validateConfiguration()
          let screenshot = await screenshotDataURL()
          if settings.includeScreenshot, screenshot == nil {
            warnings.append("Screenshot context unavailable.")
          }
          finalText = try await client.adjust(
            transcript: finalText,
            screenshotDataURL: screenshot,
            settings: settings,
            app: targetApp
          )
          .trimmingCharacters(in: .whitespacesAndNewlines)
          cleanup = .llm
        } catch {
          let fallback = fallbackTranscript(
            finalText,
            warnings: &warnings
          )
          finalText = fallback.text
          cleanup = fallback.cleanup
        }
      case .localDemo:
        finalText = DemoAdjustmentPreview().adjust(finalText)
        cleanup = .demo
      }
      try validateTranscript(finalText)
    }

    let conversion = await convertChinese(finalText)
    finalText = conversion.text
    if let warning = conversion.warning {
      warnings.append(warning)
    }
    try validateTranscript(finalText)

    return FinalizedTranscript(
      text: finalText,
      warning: warnings.joined(separator: " "),
      targetApp: targetApp,
      cleanup: cleanup
    )
  }

  /// Captures optional screen context outside the UI actor because `screencapture` is a blocking process boundary.
  private func screenshotDataURL() async -> String? {
    guard settings.includeScreenshot else {
      return nil
    }

    let provider = screenshotDataURLProvider
    return await Task.detached(priority: .userInitiated) {
      provider()
    }
    .value
  }

  private func fallbackTranscript(
    _ text: String,
    warnings: inout [String]
  ) -> (text: String, cleanup: TranscriptCleanup) {
    if settings.useLocalAdjustmentFallback {
      warnings.append("LLM adjustment failed. Used local cleanup fallback.")
      return (
        LocalAdjustmentFallback()
          .adjust(text)
          .trimmingCharacters(in: .whitespacesAndNewlines),
        .localFallback
      )
    }

    warnings.append("LLM adjustment failed. Used raw transcript.")
    return (text, .raw)
  }

  /// Runs OpenCC outside the UI actor because conversion crosses a blocking process boundary.
  private func convertChinese(_ text: String) async -> (text: String, warning: String?) {
    let converter = chineseTextConverter
    return await Task.detached(priority: .userInitiated) {
      converter.convert(text)
    }
    .value
  }

  private func validateTranscript(_ text: String) throws {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw NSError(
        domain: "Vhrase.Transcript",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "No transcript text was returned."]
      )
    }
  }
}

struct FinalizedTranscript {
  let text: String
  let warning: String
  let targetApp: FrontmostApp?
  let cleanup: TranscriptCleanup
}

enum AdjustmentExecution: Equatable {
  case provider
  case localDemo
}
