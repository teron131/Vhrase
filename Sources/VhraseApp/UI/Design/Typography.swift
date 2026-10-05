// Defines Vhrase's type hierarchy: rounded heavy SF Pro gives the interface its voice, and New York sets only the user's own words.

import SwiftUI

enum VhraseFont {
  static let pageTitle = Font.system(.largeTitle, design: .rounded, weight: .heavy)
  static let statusTitle = Font.system(.title, design: .rounded, weight: .heavy)
  static let timer = Font.system(.title3, design: .rounded, weight: .bold).monospacedDigit()
  static let title = Font.system(.title3, design: .rounded, weight: .bold)
  static let statValue = Font.system(.title, design: .rounded, weight: .heavy).monospacedDigit()
  static let headline = Font.system(.headline, design: .rounded, weight: .bold)
  /// Pills, tabs, and chips share one compact rounded label.
  static let pill = Font.system(.callout, design: .rounded, weight: .semibold)
  /// The latest dictation is set at reading size because it is the main window's primary content.
  static let transcript = Font.system(.title2, design: .serif)
  static let transcriptBody = Font.system(.body, design: .serif)
  static let caption = Font.callout
  static let micro = Font.caption.weight(.medium)
}
