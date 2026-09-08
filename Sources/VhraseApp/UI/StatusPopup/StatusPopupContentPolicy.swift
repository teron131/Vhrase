// Keeps recorder geometry stable across live updates and reserves extra space only for actionable errors.

import Foundation

enum StatusPopupContentPolicy {
  static func size(for status: AppStatus) -> CGSize {
    if case .failed = status { return CGSize(width: 340, height: 136) }
    return CGSize(width: 144, height: 52)
  }
}
