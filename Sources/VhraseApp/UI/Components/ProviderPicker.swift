// Bridges native image-and-text provider controls to SwiftUI settings without losing icons in segmented pickers.

import AppKit
import SwiftUI

@MainActor
struct ProviderPicker: NSViewRepresentable {
  enum Style {
    case menu
    case segmented
  }

  @Binding var selection: STTProvider
  var style: Style = .menu
  @Environment(\.isEnabled) private var isEnabled

  private static let providers = STTProvider.allCases

  // Decode once and preserve the supplied colors and backgrounds in both appearance modes.
  private static let icons: [STTProvider: NSImage] = {
    // Packaged apps use Contents/Resources; SwiftPM executables use their generated module bundle.
    let bundle =
      Bundle.main.resourceURL.flatMap {
        Bundle(url: $0.appendingPathComponent("Vhrase_VhraseApp.bundle"))
      } ?? Bundle.module
    return providers.reduce(into: [:]) { icons, provider in
      let name =
        switch provider {
        case .xai: "spacexai"
        case .elevenLabs: "elevenlabs_small"
        case .gemini: "google_small"
        }
      guard
        let url = bundle.url(
          forResource: name, withExtension: "svg", subdirectory: "ProviderIcons"
        ), let image = NSImage(contentsOf: url)
      else {
        return
      }
      image.size = NSSize(width: 16, height: 16)
      image.isTemplate = false
      icons[provider] = image
    }
  }()

  func makeCoordinator() -> Coordinator {
    Coordinator(selection: $selection)
  }

  /// Uses AppKit's explicit image slots because SwiftUI's macOS segmented Picker retains only label text.
  func makeNSView(context: Context) -> NSControl {
    let control: NSControl
    switch style {
    case .menu:
      let menu = NSPopUpButton(frame: .zero, pullsDown: false)
      for provider in Self.providers {
        menu.addItem(withTitle: provider.title)
        menu.lastItem?.image = Self.icons[provider]
      }
      menu.imagePosition = .imageLeading
      control = menu
    case .segmented:
      let segments = NSSegmentedControl(
        labels: Self.providers.map(\.title), trackingMode: .selectOne,
        target: nil, action: nil
      )
      for (index, provider) in Self.providers.enumerated() {
        segments.setImage(Self.icons[provider], forSegment: index)
      }
      control = segments
    }
    control.target = context.coordinator
    control.action = #selector(Coordinator.selectProvider(_:))
    control.setAccessibilityLabel("Speech provider")
    return control
  }

  /// Reflects external provider changes and the workflow's disabled state without firing selection actions.
  func updateNSView(_ control: NSControl, context: Context) {
    context.coordinator.selection = $selection
    control.isEnabled = isEnabled
    guard let index = Self.providers.firstIndex(of: selection) else { return }
    if let menu = control as? NSPopUpButton {
      menu.selectItem(at: index)
    } else if let segments = control as? NSSegmentedControl {
      segments.selectedSegment = index
    }
  }

  @MainActor
  final class Coordinator: NSObject {
    var selection: Binding<STTProvider>

    init(selection: Binding<STTProvider>) {
      self.selection = selection
    }

    /// Sends native selection changes through the existing settings binding and persistence policy.
    @objc func selectProvider(_ sender: NSControl) {
      let index: Int
      if let menu = sender as? NSPopUpButton {
        index = menu.indexOfSelectedItem
      } else if let segments = sender as? NSSegmentedControl {
        index = segments.selectedSegment
      } else {
        return
      }
      guard ProviderPicker.providers.indices.contains(index) else { return }
      selection.wrappedValue = ProviderPicker.providers[index]
    }
  }
}
