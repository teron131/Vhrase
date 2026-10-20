// Edits the single vocabulary list that speech recognition and LLM polishing both read, and flags the first term the selected provider would reject.

import SwiftUI

struct VocabularyEditor: View {
  @ObservedObject var appState: AppState

  var body: some View {
    let issue = TranscriptionContract.vocabularyIssue(in: appState.settings)
    let count = appState.settings.keytermList.count
    VStack(alignment: .leading, spacing: 10) {
      editorTile(
        "Vocabulary",
        text: appState.settingsBinding(\.keyterms),
        height: 200,
        instruction: "One term per line. They are hints: Vhrase never forces them into your text.",
        placeholder: "Vercel\nbackpropagation\nMonte Carlo"
      )

      HStack(alignment: .firstTextBaseline) {
        Text(count == 1 ? "1 unique term" : "\(count) unique terms")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
        if let issue {
          Text(issue)
            .font(.caption)
            .foregroundStyle(VhraseTheme.statusFailure)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer()
        Button("Add developer vocabulary") {
          appState.updateSettings { settings in
            let terms = [
              "Codex", "ChatGPT", "Anthropic", "Claude", "Vercel", "refactor", "schema", "JSON",
              "docstring", "backpropagation", "Monte Carlo",
            ]
            let keyterms = settings.keytermList
            let existing = Set(keyterms.map { $0.lowercased() })
            let additions = terms.filter { !existing.contains($0.lowercased()) }
            settings.keyterms = (keyterms + additions).joined(separator: "\n")
          }
        }
        .buttonStyle(AccentLinkButtonStyle())
        .font(.callout)
        .fixedSize()
        .help("Adds common developer terms without replacing your vocabulary")
      }
    }
  }
}

extension DictationSettings {
  /// How the selected provider reads the vocabulary and its limits, as the Vocabulary page shows it.
  var vocabularyHintGuidance: String {
    switch (provider, transcriptionMode) {
    case (.xai, _):
      "xAI accepts up to 100 terms, each up to 50 characters."
    case (.gemini, _):
      "Gemini accepts up to 1,000 terms; a focused list of 100 or fewer works best."
    case (.elevenLabs, .upload):
      "ElevenLabs upload accepts up to 1,000 terms; using them adds 20% to transcription cost."
    case (.elevenLabs, .realtime):
      "ElevenLabs realtime accepts up to 50 terms, each up to 20 characters; using them adds 20% to transcription cost."
    case (.openAI, _):
      "OpenAI reads these as keyword hints; a focused list works best, and terms cannot contain < or >."
    case (.vercel, _), (.parakeet, _), (.huggingFace, _):
      "\(provider.title) takes no vocabulary hints, so only polishing uses these terms."
    }
  }
}
