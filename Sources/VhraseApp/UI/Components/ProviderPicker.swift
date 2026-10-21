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
  /// Segments to offer; a location's subset shows no selection while the chosen provider belongs to another location.
  var providers: [STTProvider] = STTProvider.allCases
  var style: Style = .menu
  @Environment(\.isEnabled) private var isEnabled

  private static let allProviders = STTProvider.allCases

  // Decode once and preserve the supplied colors and backgrounds in both appearance modes.
  private static let icons: [STTProvider: NSImage] = {
    return allProviders.reduce(into: [:]) { icons, provider in
      let name =
        switch provider {
        case .xai: "spacexai"
        case .elevenLabs: "elevenlabs_small"
        case .gemini: "google_small"
        case .openAI: "openai"
        case .vercel: "vercel"
        case .parakeet: "nvidia"
        case .huggingFace: "huggingface"
        }
      guard
        let url = Bundle.vhraseResources.url(
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

  static func icon(for provider: STTProvider) -> NSImage? {
    icons[provider]
  }

  /// Matches a saved transcript's provider label, such as `Gemini · Smart` or `xAI Realtime`, to that provider's cached artwork; `Local Demo` gets a computer symbol.
  static func icon(forHistoryLabel label: String) -> NSImage? {
    if label == "Local Demo" {
      return NSImage(systemSymbolName: "desktopcomputer", accessibilityDescription: nil)
    }
    guard
      let provider = allProviders.first(where: {
        label == $0.title || label.hasPrefix("\($0.title) · ")
          || label == "\($0.title) Realtime"
      })
    else { return nil }
    return icons[provider]
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(selection: $selection, providers: providers)
  }

  /// Uses AppKit's explicit image slots because SwiftUI's macOS segmented Picker retains only label text.
  func makeNSView(context: Context) -> NSControl {
    let control: NSControl
    switch style {
    case .menu:
      // Every provider appears under its location's header; tags map items back to providers.
      let menu = NSPopUpButton(frame: .zero, pullsDown: false)
      menu.autoenablesItems = false
      for location in ProviderLocation.allCases {
        let header = NSMenuItem.sectionHeader(title: location.title)
        header.isEnabled = false
        // Headers default to tag 0, the first provider's tag, which would select the header instead of that provider.
        header.tag = -1
        menu.menu?.addItem(header)
        for provider in location.providers {
          let item = NSMenuItem(title: provider.title, action: nil, keyEquivalent: "")
          item.image = Self.icons[provider]
          item.tag = Self.allProviders.firstIndex(of: provider) ?? -1
          menu.menu?.addItem(item)
        }
      }
      menu.imagePosition = .imageLeading
      control = menu
    case .segmented:
      let segments = NSSegmentedControl(
        labels: providers.map(\.title), trackingMode: .selectOne,
        target: nil, action: nil
      )
      for (index, provider) in providers.enumerated() {
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
    if let menu = control as? NSPopUpButton {
      menu.selectItem(withTag: Self.allProviders.firstIndex(of: selection) ?? -1)
    } else if let segments = control as? NSSegmentedControl {
      segments.selectedSegmentBezelColor = NSColor(VhraseTheme.accent)
      segments.selectedSegment = providers.firstIndex(of: selection) ?? -1
    }
  }

  @MainActor
  final class Coordinator: NSObject {
    var selection: Binding<STTProvider>
    let providers: [STTProvider]

    init(selection: Binding<STTProvider>, providers: [STTProvider]) {
      self.selection = selection
      self.providers = providers
    }

    @objc func selectProvider(_ sender: NSControl) {
      if let menu = sender as? NSPopUpButton {
        guard let tag = menu.selectedItem?.tag, ProviderPicker.allProviders.indices.contains(tag)
        else { return }
        selection.wrappedValue = ProviderPicker.allProviders[tag]
      } else if let segments = sender as? NSSegmentedControl,
        providers.indices.contains(segments.selectedSegment)
      {
        selection.wrappedValue = providers[segments.selectedSegment]
      }
    }
  }
}

/// Uses native menu image slots so history filters retain provider artwork on macOS.
struct HistoryProviderPicker: NSViewRepresentable {
  @Binding var selection: String
  let providers: [String]

  func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

  func makeNSView(context: Context) -> NSPopUpButton {
    let menu = NSPopUpButton(frame: .zero, pullsDown: false)
    menu.target = context.coordinator
    menu.action = #selector(Coordinator.select(_:))
    menu.setAccessibilityLabel("History provider filter")
    return menu
  }

  func updateNSView(_ menu: NSPopUpButton, context: Context) {
    context.coordinator.selection = $selection
    let labels = ["All providers"] + providers
    if menu.itemTitles != labels {
      menu.removeAllItems()
      for label in labels {
        menu.addItem(withTitle: label)
        menu.lastItem?.image = ProviderPicker.icon(forHistoryLabel: label)
      }
    }
    menu.selectItem(at: providers.firstIndex(of: selection).map { $0 + 1 } ?? 0)
  }

  @MainActor
  final class Coordinator: NSObject {
    var selection: Binding<String>
    init(selection: Binding<String>) { self.selection = selection }
    @objc func select(_ sender: NSPopUpButton) {
      selection.wrappedValue =
        sender.indexOfSelectedItem == 0 ? "" : sender.titleOfSelectedItem ?? ""
    }
  }
}
