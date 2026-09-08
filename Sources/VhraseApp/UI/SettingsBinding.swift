// Adapts editable SwiftUI controls to AppState's settings persistence and shortcut-update policy.

import SwiftUI

extension AppState {
  /// Routes every settings edit through normalization and persistence, including controls in the menu bar.
  func settingsBinding<Value>(
    _ keyPath: WritableKeyPath<DictationSettings, Value>
  ) -> Binding<Value> {
    Binding(
      get: { self.settings[keyPath: keyPath] },
      set: { value in
        self.updateSettings { settings in
          settings[keyPath: keyPath] = value
        }
      }
    )
  }
}
