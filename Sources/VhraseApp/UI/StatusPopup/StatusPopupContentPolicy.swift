// Keeps recorder height stable across every workflow state while reserving error width for recovery controls.

import Foundation

enum StatusPopupContentPolicy {
  private static let height: CGFloat = 52

  static func size(for status: AppStatus) -> CGSize {
    if case .failed = status { return CGSize(width: 340, height: height) }
    return CGSize(width: 144, height: height)
  }
}
