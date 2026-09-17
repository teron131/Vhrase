// Defines the stable destinations used by sidebar navigation, menu actions, and saved window selection.

enum MainWindowTab: String, CaseIterable, Hashable, Identifiable {
  case dictate
  case capture
  case output
  case history
  case system

  var id: String { rawValue }

  init(storedRawValue: String) {
    self = MainWindowTab(rawValue: storedRawValue) ?? .dictate
  }

  var title: String {
    switch self {
    case .dictate: "Dictate"
    case .history: "History"
    case .capture: "Transcription"
    case .output: "Refinement"
    case .system: "System"
    }
  }

  var detail: String {
    switch self {
    case .dictate: "Record and review"
    case .history: "Saved transcripts"
    case .capture: "Speech and shortcut"
    case .output: "Writing and delivery"
    case .system: "Access and readiness"
    }
  }

  var systemImage: String {
    switch self {
    case .dictate: "waveform"
    case .history: "clock.arrow.circlepath"
    case .capture: "mic.and.signal.meter"
    case .output: "text.badge.checkmark"
    case .system: "wrench.and.screwdriver"
    }
  }
}
