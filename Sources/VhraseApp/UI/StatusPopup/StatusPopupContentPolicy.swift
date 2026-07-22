// Defines when the recorder HUD expands to expose live or finalized transcript output.

import Foundation

enum StatusPopupContentPolicy {
    static func showsTranscript(
        status: AppStatus,
        hasLiveTranscript: Bool,
        hasFinalTranscript: Bool
    ) -> Bool {
        switch status {
        case .recording:
            hasLiveTranscript
        case .completed:
            hasFinalTranscript
        case .failed:
            true
        case .idle, .preparing, .transcribing, .adjusting:
            false
        }
    }
}
