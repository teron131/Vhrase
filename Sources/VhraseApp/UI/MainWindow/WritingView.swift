// Owns how polished text should read: the writing-style preset with its individual choices, and instructions that take priority over them; automatic and double-tap polishing both follow it.

import SwiftUI

struct WritingView: View {
  @ObservedObject var appState: AppState

  var body: some View {
    mainWindowPage {
      pageHeader(
        "Writing",
        description:
          "How polished text should read. Automatic and double-tap polishing both follow it."
      )

      PolishPreferencesEditor(appState: appState)

      settingsGroup("Additional instructions") {
        editorTile(
          "Additional instructions",
          text: appState.settingsBinding(\.adjustmentPrompt),
          height: 96,
          instruction:
            "Optional instructions for the LLM. These take priority over the writing preferences above.",
          placeholder: "Keep Jira issue keys unchanged. Use British spelling."
        )
        .settingsRowStyle()
      }
    }
    .disabled(appState.presentation.workflowControlsAreDisabled)
    .mainWindowEvents(appState: appState)
  }
}
