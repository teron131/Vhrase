// Lets the user follow macOS or fix Vhrase's light or dark palette, and applies that choice to every window.

import AppKit

/// Which of the theme's two palettes Vhrase shows; the recorder pill stays dark under all three.
enum AppearancePreference: String, CaseIterable, Identifiable {
  case system
  case light
  case dark

  /// The defaults key shared by the read at launch and the picker in the sidebar's corner.
  static let storageKey = "appearance"

  /// The saved choice, read at launch before any view exists to hold it.
  static var saved: AppearancePreference {
    UserDefaults.standard.string(forKey: storageKey).flatMap(AppearancePreference.init) ?? .system
  }

  var id: String { rawValue }

  var title: String {
    switch self {
    case .system: "System"
    case .light: "Light"
    case .dark: "Dark"
    }
  }

  /// The familiar display, sun, and moon marks for the three choices.
  var systemImage: String {
    switch self {
    case .system: "display"
    case .light: "sun.max"
    case .dark: "moon"
    }
  }

  /// Sets the app-wide appearance, so the main window, menu-bar pop-up, and dialogs change together; System hands the choice back to macOS.
  @MainActor
  func apply() {
    NSApp.appearance =
      switch self {
      case .system: nil
      case .light: NSAppearance(named: .aqua)
      case .dark: NSAppearance(named: .darkAqua)
      }
  }
}
