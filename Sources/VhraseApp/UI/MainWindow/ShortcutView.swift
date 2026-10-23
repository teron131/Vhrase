// Owns the global shortcut: its key, what each press does, and the macOS access that reaching other apps needs; ends key capture when its window or destination is left.

import SwiftUI

struct ShortcutView: View {
  @ObservedObject var appState: AppState
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isCapturingHotkey = false
  private var presentation: DictationPresentation { appState.presentation }

  var body: some View {
    mainWindowPage {
      pageHeader(
        "Shortcut",
        description: "Start dictating in any app without leaving what you're writing."
      )
      keyCard
      accessNotice
      gestures
    }
    .disabled(presentation.workflowControlsAreDisabled)
    .mainWindowEvents(
      appState: appState, blocksEscape: isCapturingHotkey, onDeactivate: cancelShortcutCapture
    )
    .onDisappear(perform: cancelShortcutCapture)
  }

  private var keyCard: some View {
    settingsGroup {
      VStack(spacing: 14) {
        KeyCap(text: appState.settings.hotkeyDisplay, prominence: .hero)
          .scaleEffect(isCapturingHotkey ? 1.06 : 1)

        Text(keyCaption)
          .font(.callout)
          .foregroundStyle(isCapturingHotkey ? VhraseTheme.accent : Color.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 460)
          .contentTransition(.interpolate)

        HStack(spacing: 10) {
          Button {
            appState.beginShortcutCapture()
            isCapturingHotkey = true
          } label: {
            Label(
              isCapturingHotkey ? "Listening" : "Change shortcut", systemImage: "record.circle")
          }
          .buttonStyle(.borderedProminent)
          .disabled(isCapturingHotkey)

          Button {
            appState.disableShortcut()
          } label: {
            Label("Disable", systemImage: "slash.circle")
          }
          .buttonStyle(.bordered)
          .disabled(appState.settings.hotkeyPreset == .disabled)
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 16)
      .settingsRowStyle()
      .animation(
        VhraseMotion.respectingReduceMotion(VhraseMotion.stateSpring, reduceMotion: reduceMotion),
        value: isCapturingHotkey
      )

      settingsRow("Preset", detail: "Pick a common shortcut, or record any shortcut above.") {
        Picker("Preset", selection: appState.settingsBinding(\.hotkeyPreset)) {
          ForEach(appState.settings.availableHotkeyPresets) { preset in
            Text(preset.display).tag(preset)
          }
        }
        .labelsHidden()
        .fixedSize()
      }
    }
    .background {
      if isCapturingHotkey {
        HotkeyCaptureView(isCapturing: $isCapturingHotkey) { hotkey in
          appState.setCustomShortcut(hotkey)
        } onFnCapture: {
          appState.setFnShortcut()
        } onCancel: {
          appState.cancelShortcutCapture()
        } onUnsupported: { message in
          appState.rejectShortcutCapture(message)
        }
        .frame(width: 1, height: 1)
        .accessibilityHidden(true)
      }
    }
  }

  private var keyCaption: String {
    if isCapturingHotkey {
      return "Press Fn/Globe or another shortcut. Press Escape to cancel."
    }
    if appState.settings.hotkeyPreset == .disabled {
      return "No shortcut. Start dictation from the menu bar or Dictation instead."
    }
    return "Works in every app, wherever your cursor is."
  }

  /// Accessibility lets the shortcut and double-tap polishing reach other apps; Fn/Globe can fall back on Input Monitoring.
  @ViewBuilder private var accessNotice: some View {
    let fnNeedsAccess = appState.settings.hotkeyPreset == .fn && !presentation.selectedShortcutReady
    let polishNeedsAccess = appState.settings.shortcutGestures.doubleTapToPolish
    let message =
      switch (fnNeedsAccess, polishNeedsAccess) {
      case (true, true):
        "Fn/Globe and double-tap polishing need Accessibility to work in other apps."
      case (true, false): "Fn/Globe needs Accessibility to work in other apps."
      case (false, _):
        "Double-tap polishing needs Accessibility to read and replace text in other apps."
      }
    if !presentation.permissions.isReady(.accessibility), fnNeedsAccess || polishNeedsAccess {
      NoticeCard(
        message,
        systemImage: "exclamationmark.triangle",
        color: VhraseTheme.statusWarning,
        actionTitle: presentation.insertionPermissionActionTitle,
        action: { appState.handlePermissionAction(.accessibility) }
      )
    }
  }

  private var gestures: some View {
    let gestures = appState.settings.shortcutGestures
    return Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 8) {
      GridRow {
        groupHeading("Dictate")
          .gridCellColumns(2)
        groupHeading("Restyle")
        groupHeading("Cancel")
      }

      GridRow {
        GestureTile(
          title: "Tap",
          isOn: appState.settingsBinding(\.shortcutGestures.tapToToggle),
          isLocked: !gestures.holdToTalk,
          detail: "Starts recording. Tap again to finish.",
          timeline: GestureTimeline(presses: [0.06...0.15, 0.80...0.89], recording: 0.06...0.84)
        )
        GestureTile(
          title: "Hold",
          isOn: appState.settingsBinding(\.shortcutGestures.holdToTalk),
          isLocked: !gestures.tapToToggle,
          detail: "Records while you hold the key and finishes when you let go.",
          timeline: GestureTimeline(presses: [0.06...0.86], recording: 0.06...0.86)
        )
        GestureTile(
          title: "Double-tap",
          isOn: appState.settingsBinding(\.shortcutGestures.doubleTapToPolish),
          detail:
            "Restyles selected text, or the whole field if nothing is selected, with \(appState.settings.polishStyle.title). Undo with Command-Z in the target app.",
          timeline: .doubleTap
        )
        GestureTile(
          title: "Esc",
          keyCap: "esc",
          detail: "Cancels the recording. Nothing is pasted or saved.",
          timeline: GestureTimeline(
            presses: [0.62...0.71], recording: 0.06...0.66, outcome: "xmark", outcomeAt: 0.86)
        )
      }

      GridRow {
        Text("Keep tap or hold on, so the shortcut can always start dictation.")
          .gridCellColumns(2)
        HStack(spacing: 6) {
          Capsule()
            .fill(VhraseTheme.statusRecording)
            .frame(width: 16, height: 6)
          Text("Recording")
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .gridCellColumns(2)
        .accessibilityHidden(true)
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
  }

  private func groupHeading(_ title: String) -> some View {
    Text(title)
      .font(VhraseFont.headline)
      .accessibilityAddTraits(.isHeader)
  }

  private func cancelShortcutCapture() {
    guard isCapturingHotkey else {
      return
    }
    isCapturingHotkey = false
    appState.cancelShortcutCapture()
  }
}

private struct GestureTile: View {
  let title: String
  /// Shown instead of the title for a press on a key other than the shortcut.
  var keyCap: String?
  var isOn: Binding<Bool>?
  /// Keeps the last dictation press on, so the shortcut can always start dictation.
  var isLocked = false
  let detail: String
  let timeline: GestureTimeline

  var body: some View {
    let isActive = isOn?.wrappedValue ?? true
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        if let keyCap {
          KeyCap(text: keyCap)
            .accessibilityLabel(title)
        } else {
          Text(title)
            .font(VhraseFont.headline)
        }
        Spacer(minLength: 8)
        if let isOn {
          VhraseSwitch(title: title, isOn: isOn)
            .disabled(isLocked)
            .help(isLocked ? "Tap or hold must stay on to start dictation." : "")
        }
      }
      .frame(minHeight: 26)
      Group {
        timeline
          .accessibilityHidden(true)
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .opacity(isActive ? 1 : 0.4)
    }
    .padding(14)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .surface()
    .accessibilityElement(children: .contain)
  }
}
