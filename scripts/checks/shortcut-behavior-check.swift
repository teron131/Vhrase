// Verifies production shortcut policy across toggle, hold, startup, and processing phases.

@main
struct ShortcutBehaviorCheck {
  static func main() {
    precondition(ShortcutBehavior.toggle.action(for: .pressed, status: .idle) == .toggleRecording)
    precondition(
      ShortcutBehavior.toggle.action(for: .pressed, status: .preparing) == .toggleRecording)
    precondition(
      ShortcutBehavior.toggle.action(for: .pressed, status: .recording) == .toggleRecording)
    precondition(ShortcutBehavior.toggle.action(for: .released, status: .recording) == .none)
    precondition(ShortcutBehavior.toggle.action(for: .pressed, status: .transcribing) == .none)
    precondition(
      ShortcutBehavior.holdToRecord.action(for: .pressed, status: .idle) == .beginRecording)
    precondition(ShortcutBehavior.holdToRecord.action(for: .pressed, status: .recording) == .none)
    precondition(
      ShortcutBehavior.holdToRecord.action(for: .released, status: .preparing) == .cancelRecording)
    precondition(
      ShortcutBehavior.holdToRecord.action(for: .released, status: .recording) == .finishRecording)
    precondition(
      ShortcutBehavior.holdToRecord.action(for: .released, status: .transcribing) == .none)

    var settings = DictationSettings.defaults
    precondition(!settings.availableHotkeyPresets.contains(.custom))
    settings.customHotkey = CustomHotkey(keyCode: 0, modifiers: 0, display: "Custom Test")
    precondition(settings.availableHotkeyPresets.contains(.custom))
    print("shortcut behavior ok")
  }
}
