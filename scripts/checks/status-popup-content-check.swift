// Verifies every workflow state uses one stable recorder capsule.

import Foundation

@main
struct StatusPopupContentCheck {
  static func main() {
    let expectedSize = CGSize(width: 184, height: 52)
    for status: AppStatus in [
      .idle, .preparing, .recording, .transcribing, .adjusting, .completed,
      .failed("No connection"),
    ] {
      let size = StatusPopupContentPolicy.size(for: status)
      precondition(size.width == expectedSize.width && size.height == expectedSize.height)
    }

    print("Status popup content checks passed")
  }
}
