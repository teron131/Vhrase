// Edits the single vocabulary shared by speech recognition and LLM polishing, with the selected provider's limits.

import SwiftUI

struct VocabularyEditor: View {
  @ObservedObject var appState: AppState

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      editorTile(
        "Shared vocabulary",
        systemImage: "tag",
        text: appState.settingsBinding(\.keyterms),
        height: 96,
        instruction:
          "Names and terms used as hints by speech recognition and LLM polishing. One per line; never forced into your text.",
        placeholder: "Vercel\nbackpropagation\nMonte Carlo"
      )

      HStack {
        Text("\(appState.settings.keytermList.count) unique terms")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
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
        .help("Adds common developer terms without replacing your vocabulary")
      }

      Text(keytermGuidance)
        .font(.caption)
        .foregroundStyle(
          appState.transcriptionConfigurationIssue == nil ? Color.secondary : Color.red)
    }
  }

  private var keytermGuidance: String {
    if let issue = appState.transcriptionConfigurationIssue {
      return issue
    }
    switch (appState.settings.provider, appState.settings.transcriptionMode) {
    case (.xai, _):
      return "xAI accepts up to 100 keyterms, with at most 50 characters in each term."
    case (.gemini, _):
      return
        "Gemini accepts up to 1,000 terms; a focused list of 100 or fewer works best. Your vocabulary is shared across providers."
    case (.elevenLabs, .upload):
      return
        "ElevenLabs upload accepts up to 1,000 keyterms; using keyterms adds 20% to transcription usage."
    case (.elevenLabs, .realtime):
      return
        "ElevenLabs realtime accepts up to 50 keyterms of 20 characters each; using keyterms adds 20% to transcription usage."
    }
  }

}
