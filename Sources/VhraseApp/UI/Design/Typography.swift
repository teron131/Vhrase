// Defines the type hierarchy used across Vhrase's recording surfaces.

import SwiftUI

enum VhraseFont {
    static let pageTitle = Font.system(.largeTitle, design: .default, weight: .semibold)
    static let timer = Font.system(.title2, design: .rounded, weight: .semibold).monospacedDigit()
    static let title = Font.system(.title3, design: .default, weight: .semibold)
    static let statValue = Font.system(.title2, design: .rounded, weight: .semibold).monospacedDigit()
    static let headline = Font.headline.weight(.semibold)
    static let transcript = Font.system(.body, design: .serif)
    static let caption = Font.callout
    static let micro = Font.caption.weight(.medium)
}
