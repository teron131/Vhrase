// Verifies stable recording-pill height and the wider error recovery surface.

import Foundation

@main
struct StatusPopupContentCheck {
  static func main() {
    let pillSize = CGSize(width: 144, height: 52)
    for status: AppStatus in [.idle, .preparing, .recording, .transcribing, .adjusting, .completed]
    {
      precondition(StatusPopupContentPolicy.size(for: status) == pillSize)
    }
    let errorSize = StatusPopupContentPolicy.size(for: .failed("No connection"))
    precondition(errorSize.width > pillSize.width)
    precondition(errorSize.height == pillSize.height)

    print("Status popup content checks passed")
  }
}
