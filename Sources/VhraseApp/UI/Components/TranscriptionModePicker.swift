// Presents every transcription transport while disabling provider-incompatible segments at the native control boundary.

import AppKit
import SwiftUI

@MainActor
struct TranscriptionModePicker: NSViewRepresentable {
  @Binding var selection: TranscriptionMode
  let enabledModes: [TranscriptionMode]
  @Environment(\.isEnabled) private var isEnabled

  private static let modes = TranscriptionMode.allCases

  func makeCoordinator() -> Coordinator {
    Coordinator(selection: $selection)
  }

  func makeNSView(context: Context) -> NSSegmentedControl {
    let control = NSSegmentedControl(
      labels: Self.modes.map(\.title),
      trackingMode: .selectOne,
      target: context.coordinator,
      action: #selector(Coordinator.selectMode(_:))
    )
    control.setAccessibilityLabel("Transcription mode")
    return control
  }

  /// Keeps unsupported modes visible while making the native segment genuinely noninteractive and accessibility-disabled.
  func updateNSView(_ control: NSSegmentedControl, context: Context) {
    context.coordinator.selection = $selection
    control.selectedSegmentBezelColor = NSColor(VhraseTheme.accent)
    for (index, mode) in Self.modes.enumerated() {
      control.setEnabled(isEnabled && enabledModes.contains(mode), forSegment: index)
    }
    guard let selectedIndex = Self.modes.firstIndex(of: selection) else {
      return
    }
    control.selectedSegment = selectedIndex
  }

  @MainActor
  final class Coordinator: NSObject {
    var selection: Binding<TranscriptionMode>

    init(selection: Binding<TranscriptionMode>) {
      self.selection = selection
    }

    @objc func selectMode(_ sender: NSSegmentedControl) {
      let index = sender.selectedSegment
      guard TranscriptionModePicker.modes.indices.contains(index),
        sender.isEnabled(forSegment: index)
      else {
        return
      }
      selection.wrappedValue = TranscriptionModePicker.modes[index]
    }
  }
}
