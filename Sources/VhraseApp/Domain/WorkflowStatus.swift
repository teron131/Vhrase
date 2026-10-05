// Defines the workflow phases and the recording, processing, and feedback actions each phase permits.

import Foundation

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
