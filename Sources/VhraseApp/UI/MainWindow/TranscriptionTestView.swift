// Shows a short recognition check beside provider setup and keeps its raw result separate from dictation history.

import AppKit
import SwiftUI

struct TranscriptionTestView: View {
  @ObservedObject var appState: AppState
  @ObservedObject var test: TranscriptionTest

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(
        "Record a short phrase with \(appState.settings.provider.title) · \(appState.settings.transcriptionModeTitle). Recording stops after five seconds."
      )
      .font(VhraseFont.caption)
      .foregroundStyle(VhraseTheme.inkSecondary)
      .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 12) {
        switch test.state {
        case .idle, .completed, .failed:
          Button("Record test", systemImage: "mic") { appState.startTranscriptionTest() }
            .buttonStyle(.borderedProminent)
            .disabled(!appState.canStartRecording)
        case .starting:
          ProgressView().controlSize(.small)
          Text("Starting microphone…")
        case .recording(let secondsRemaining):
          Button("Stop and transcribe", systemImage: "stop.fill") { test.stopAndTranscribe() }
            .buttonStyle(.borderedProminent)
          Text("Recording · \(secondsRemaining)s remaining")
        case .transcribing:
          ProgressView().controlSize(.small)
          Text("Recognizing speech…")
        }

        if test.state.isActive {
          Button("Cancel") { test.cancel() }
            .buttonStyle(.bordered)
        }
      }
      .font(.callout)

      switch test.state {
      case .completed(let text):
        HStack(alignment: .top, spacing: 16) {
          Text(text)
            .font(VhraseFont.transcriptBody)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
          Button("Copy", systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
        }
      case .failed(let message):
        Text(message)
          .font(VhraseFont.caption)
          .foregroundStyle(VhraseTheme.statusWarning)
          .textSelection(.enabled)
      case .idle, .starting, .recording, .transcribing:
        if !test.partialTranscript.isEmpty {
          Text(test.partialTranscript)
            .font(VhraseFont.transcriptBody)
            .foregroundStyle(VhraseTheme.inkSecondary)
            .textSelection(.enabled)
        }
      }

      Text(
        "Shows the recognized text without LLM polishing, pasting, or saving to History. \(appState.settings.provider.location == .cloud ? "Test audio is sent to \(appState.settings.provider.title) and uses your transcription allowance." : "Test audio stays on this Mac.")"
      )
      .font(VhraseFont.caption)
      .foregroundStyle(VhraseTheme.inkSecondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }
}
