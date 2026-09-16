// Keeps one stable recorder capsule across every workflow state.

import Foundation

enum StatusPopupContentPolicy {
  private static let capsuleSize = CGSize(width: 184, height: 52)

  static func size(for _: AppStatus) -> CGSize {
    capsuleSize
  }
}
