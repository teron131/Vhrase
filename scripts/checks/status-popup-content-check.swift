// Verifies that the recorder HUD exposes live and finalized transcript output in the relevant workflow states.

import Foundation

@main
struct StatusPopupContentCheck {
  static func main() {
    precondition(
      StatusPopupContentPolicy.showsTranscript(
        status: .recording,
        hasLiveTranscript: true,
        hasFinalTranscript: false
      )
    )
    precondition(
      StatusPopupContentPolicy.showsTranscript(
        status: .completed,
        hasLiveTranscript: false,
        hasFinalTranscript: true
      )
    )
    precondition(
      !StatusPopupContentPolicy.showsTranscript(
        status: .completed,
        hasLiveTranscript: false,
        hasFinalTranscript: false
      )
    )
    precondition(
      !StatusPopupContentPolicy.showsTranscript(
        status: .adjusting,
        hasLiveTranscript: true,
        hasFinalTranscript: false
      )
    )

    print("Status popup content checks passed")
  }
}
