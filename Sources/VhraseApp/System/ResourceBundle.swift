// Locates the files SwiftPM packages with the app: provider marks and the Hugging Face helper script.

import Foundation

extension Bundle {
  /// Packaged apps keep SwiftPM's resource bundle in Contents/Resources; SwiftPM executables use their generated module bundle.
  static let vhraseResources: Bundle =
    Bundle.main.resourceURL.flatMap {
      Bundle(url: $0.appendingPathComponent("Vhrase_VhraseApp.bundle"))
    } ?? .module
}
