// Finalizes provider transcripts through LLM polishing, Chinese conversion, and validation policy.

import Foundation

@MainActor
struct TranscriptFinalizer {
  let settings: DictationSettings
  let llmAPIKey: String
  let screenshotDataURLProvider: @Sendable (FrontmostApp?, ScreenshotResolution) async -> String?
  let chineseTextConverter: ChineseTextConverter

  init(
    settings: DictationSettings,
    llmAPIKey: String,
    screenshotDataURLProvider:
      @escaping @Sendable (FrontmostApp?, ScreenshotResolution) async -> String? = {
        await ScreenContext().displayJPEGDataURL(showing: $0, resolution: $1)
      },
    chineseTextConverter: ChineseTextConverter = ChineseTextConverter()
  ) {
    self.settings = settings
    self.llmAPIKey = llmAPIKey
    self.screenshotDataURLProvider = screenshotDataURLProvider
    self.chineseTextConverter = chineseTextConverter
  }

  func finalize(
    _ result: TranscriptionResult,
    adjustment: AdjustmentExecution,
    targetApp: FrontmostApp?
  ) async throws -> FinalizedTranscript {
    var finalText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    var warnings: [String] = []

    try validateTranscript(finalText)

    var cleanup: TranscriptCleanup = .raw
    var refinement: LLMRefinement?

    if settings.adjustWithLLM {
      switch adjustment {
      case .provider:
        do {
          let client = LLMAdjustmentClient(
            apiKey: llmAPIKey,
            baseURL: settings.adjustmentBaseURL
          )
          try client.validateConfiguration()
          let screenshot = await screenshotDataURL(showing: targetApp)
          if settings.includeScreenshot, screenshot == nil {
            warnings.append("Screenshot context unavailable.")
          }
          let appliedRefinement = try await client.adjust(
            transcript: finalText,
            screenshotDataURL: screenshot,
            settings: settings,
            app: targetApp
          )
          refinement = appliedRefinement
          finalText = appliedRefinement.output
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
      cleanup: cleanup,
      refinement: refinement
    )
  }

  private func screenshotDataURL(showing targetApp: FrontmostApp?) async -> String? {
    guard settings.includeScreenshot else {
      return nil
    }
    return await screenshotDataURLProvider(targetApp, settings.screenshotResolution)
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
  let cleanup: TranscriptCleanup
  let refinement: LLMRefinement?
}

enum AdjustmentExecution: Equatable {
  case provider
  case localDemo
}
