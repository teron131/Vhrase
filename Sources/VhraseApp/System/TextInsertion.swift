// Inserts finalized text while preserving or retaining the user's clipboard as configured.

import AppKit
import Foundation

protocol TextPasteboard: AnyObject {
  var changeCount: Int { get }
  var pasteboardItems: [NSPasteboardItem]? { get }

  @discardableResult
  func clearContents() -> Int

  func setString(
    _ string: String,
    forType dataType: NSPasteboard.PasteboardType
  ) -> Bool

  func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool
}

extension NSPasteboard: TextPasteboard {}

@MainActor
struct TextInsertion {
  private let pasteboard: any TextPasteboard
  private let restoreDelay: Duration
  private let postPasteShortcut: () throws -> Void

  init() {
    self.init(
      pasteboard: NSPasteboard.general,
      restoreDelay: .milliseconds(150),
      postPasteShortcut: Self.postPasteShortcutEvent
    )
  }

  init(
    pasteboard: any TextPasteboard,
    restoreDelay: Duration,
    postPasteShortcut: @escaping () throws -> Void
  ) {
    self.pasteboard = pasteboard
    self.restoreDelay = restoreDelay
    self.postPasteShortcut = postPasteShortcut
  }

  /// Replaces the active pasteboard with finalized text and reports a failed write.
  func copy(_ text: String) throws {
    pasteboard.clearContents()
    guard pasteboard.setString(text, forType: .string) else {
      throw TextInsertionError.copyFailed
    }
  }

  /// Posts finalized text through Command-V and reports whether it remains on the clipboard.
  func paste(
    _ text: String,
    keepOnClipboard: Bool
  ) async throws -> Bool {
    let snapshot = PasteboardSnapshot(pasteboard)
    try copy(text)
    let transcriptChangeCount = pasteboard.changeCount
    try postPasteShortcut()

    guard !keepOnClipboard else {
      return true
    }

    // Restoration is cleanup; cancellation must not leave Vhrase's transient text behind.
    try? await Task.sleep(for: restoreDelay)
    guard pasteboard.changeCount == transcriptChangeCount else {
      return false
    }
    guard snapshot.restore(to: pasteboard) else {
      try copy(text)
      return true
    }
    return false
  }

  private static func postPasteShortcutEvent() throws {
    let source = CGEventSource(stateID: .combinedSessionState)
    guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
      let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
    else {
      throw TextInsertionError.pasteEventUnavailable
    }
    down.flags = .maskCommand
    up.flags = .maskCommand
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
  }
}

private struct PasteboardSnapshot {
  let items: [NSPasteboardItem]

  init(_ pasteboard: any TextPasteboard) {
    items =
      pasteboard.pasteboardItems?.map { source in
        let item = NSPasteboardItem()
        for type in source.types {
          if let data = source.data(forType: type) {
            item.setData(data, forType: type)
          }
        }
        return item
      } ?? []
  }

  /// Replaces Vhrase's transient transcript after the caller confirms the pasteboard is unchanged.
  func restore(to pasteboard: any TextPasteboard) -> Bool {
    pasteboard.clearContents()
    return items.isEmpty || pasteboard.writeObjects(items)
  }
}

private enum TextInsertionError: LocalizedError {
  case copyFailed
  case pasteEventUnavailable

  var errorDescription: String? {
    switch self {
    case .copyFailed:
      "Could not copy the transcript to the clipboard."
    case .pasteEventUnavailable:
      "Could not create the paste keyboard event. The transcript remains on the clipboard."
    }
  }
}
