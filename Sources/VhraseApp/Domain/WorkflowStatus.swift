// Defines setup diagnostics and the state machine exposed by the dictation workflow.

import Foundation

enum SetupDiagnosticSeverity: Equatable, Sendable {
  case ready
  case attention
  case info
}

struct SetupDiagnostic: Identifiable, Sendable {
  let id: String
  let title: String
  let detail: String
  let systemImage: String
  let severity: SetupDiagnosticSeverity
}

enum AppStatus: Equatable, Sendable {
  case idle
  case preparing
  case recording
  case transcribing
  case adjusting
  case completed
  case failed(String)

  var title: String {
    switch self {
    case .idle: "Ready"
    case .preparing: "Starting…"
    case .recording: "Recording…"
    case .transcribing: "Transcribing…"
    case .adjusting: "Adjusting…"
    case .completed: "Complete"
    case .failed(let message): "Failed: \(message)"
    }
  }

  var isProcessing: Bool {
    switch self {
    case .transcribing, .adjusting: true
    default: false
    }
  }

  var showsWorkflowPopup: Bool {
    switch self {
    case .preparing, .recording, .transcribing, .adjusting, .completed, .failed: true
    case .idle: false
    }
  }

  var canStartRecording: Bool {
    switch self {
    case .idle, .completed, .failed: true
    case .preparing, .recording, .transcribing, .adjusting: false
    }
  }
}
