// Owns where finished text goes: back into the app you were typing in, onto the clipboard, and into History.

import SwiftUI

struct DeliveryView: View {
  @ObservedObject var appState: AppState
  let navigation: MainWindowNavigation
  private var presentation: DictationPresentation { appState.presentation }

  var body: some View {
    mainWindowPage {
      pageHeader(
        "Delivery",
        description: "Finished text goes back to where you were typing."
      )

      settingsGroup("Your app") {
        settingsRow(
          "Paste where you were typing",
          detail:
            "Vhrase remembers the app you were in when recording began and pastes there. If it can't, the text stays on your clipboard."
        ) {
          if let actionTitle = presentation.insertionPermissionActionTitle {
            Button(actionTitle) { appState.handlePermissionAction(.accessibility) }
              .buttonStyle(.borderedProminent)
          } else {
            Label("Allowed", systemImage: "checkmark.circle.fill")
              .font(.caption.weight(.medium))
              .foregroundStyle(VhraseTheme.statusSuccess)
          }
        }
        settingsRow(
          "Double-tap polishing",
          detail:
            "Replaces the selected text in place, and only if it hasn't changed while the model worked. Press Command-Z in that app to undo."
        ) {
          if !appState.settings.shortcutGestures.doubleTapToPolish {
            Text("Off in Shortcut")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }

      settingsGroup("Clipboard") {
        settingsToggle(
          "Keep a copy on the clipboard",
          detail:
            "Leaves the text ready to paste somewhere else. When off, what you had copied before comes back after pasting.",
          isOn: appState.settingsBinding(\.keepTranscriptOnClipboard)
        )
      }

      settingsGroup("History") {
        settingsRow(
          appState.savesTranscriptHistory ? "Saved to History" : "Not saved",
          detail: appState.savesTranscriptHistory
            ? "Finished transcripts are kept on this Mac, where you can search and copy them."
            : "History saving is off, so finished transcripts are not kept."
        ) {
          Button("Open History") { navigation.open(.history) }
            .buttonStyle(AccentLinkButtonStyle())
        }
      }
    }
    .disabled(presentation.workflowControlsAreDisabled)
    .mainWindowEvents(appState: appState)
  }
}
