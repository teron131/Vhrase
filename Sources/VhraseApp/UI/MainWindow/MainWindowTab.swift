// Defines the main window's destinations, the order of the dictation route the sidebar draws, and the navigation pages use to send people to the owner of a setting.

import SwiftUI

enum MainWindowTab: String, CaseIterable, Hashable, Identifiable {
  case dictation
  case history
  case shortcut
  case microphone
  case transcription
  case polishing
  case delivery
  case vocabulary
  case system

  static let route: [MainWindowTab] = [
    .shortcut, .microphone, .transcription, .polishing, .delivery,
  ]

  var id: String { rawValue }

  init(storedRawValue: String) {
    self = MainWindowTab(rawValue: storedRawValue) ?? .dictation
  }

  var title: String {
    switch self {
    case .dictation: "Dictation"
    case .history: "History"
    case .shortcut: "Shortcut"
    case .microphone: "Microphone"
    case .transcription: "Transcription"
    case .polishing: "Polishing"
    case .delivery: "Delivery"
    case .vocabulary: "Vocabulary"
    case .system: "System"
    }
  }

  var detail: String {
    switch self {
    case .dictation: "Record and review"
    case .history: "Saved transcripts"
    case .shortcut: "How dictation starts and stops"
    case .microphone: "What Vhrase hears"
    case .transcription: "Who turns speech into text"
    case .polishing: "How text is polished"
    case .delivery: "Where finished text goes"
    case .vocabulary: "Names and terms to get right"
    case .system: "Keys and macOS access"
    }
  }

  var systemImage: String {
    switch self {
    case .dictation: "waveform"
    case .history: "clock.arrow.circlepath"
    case .shortcut: "keyboard"
    case .microphone: "mic"
    case .transcription: "text.bubble"
    case .polishing: "wand.and.stars"
    case .delivery: "text.insert"
    case .vocabulary: "book.closed"
    case .system: "gearshape"
    }
  }
}

extension DictationPresentation {
  var configurationIssueTab: MainWindowTab? {
    guard let issue = transcriptionConfigurationIssue else { return nil }
    if issue == vocabularyIssue { return .vocabulary }
    if issue == restyleIssue { return .polishing }
    return .transcription
  }
}

struct MainWindowNavigation {
  let selection: Binding<MainWindowTab>
  let credentialRequest: Binding<SecretKey?>

  func open(_ tab: MainWindowTab) {
    selection.wrappedValue = tab
  }

  func openCredential(_ key: SecretKey) {
    credentialRequest.wrappedValue = key
    selection.wrappedValue = .system
  }
}
