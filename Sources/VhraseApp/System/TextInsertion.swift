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

struct TextInsertionContext: Equatable {
  let precedingCharacter: Character?
  let hasSelection: Bool
}

@MainActor
struct TextInsertion {
  /// How long finalized text stays on the clipboard after Command-V before the previous clipboard returns.
  /// The target app reads the clipboard only when it handles the shortcut, and that read leaves no trace Vhrase can observe, so a busy or just-activated app that handles it late pastes whatever is on the clipboard by then.
  /// At 150 ms that was occasionally the restored clipboard instead of the transcript; a second leaves a wide margin while a copy the user makes in the meantime still wins.
  private static let clipboardRestoreDelay: Duration = .seconds(1)

  private let pasteboard: any TextPasteboard
  private let restoreDelay: Duration
  private let postPasteShortcut: () throws -> Void

  init() {
    self.init(
      pasteboard: NSPasteboard.general,
      restoreDelay: Self.clipboardRestoreDelay,
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
  /// Cancellation before insertion leaves the editor and clipboard untouched; cancellation afterward still restores the clipboard.
  func paste(
    _ text: String,
    keepOnClipboard: Bool,
    context: TextInsertionContext? = nil
  ) async throws -> Bool {
    try Task.checkCancellation()
    let snapshot = PasteboardSnapshot(pasteboard)
    let insertionText = Self.preparedText(text, context: context)
    try copy(insertionText)
    let transcriptChangeCount = pasteboard.changeCount
    try postPasteShortcut()

    if keepOnClipboard && insertionText == text { return true }

    // Restoration is cleanup; cancellation must not leave Vhrase's transient text behind.
    try? await Task.sleep(for: restoreDelay)
    guard pasteboard.changeCount == transcriptChangeCount else {
      return false
    }
    if keepOnClipboard || !snapshot.restore(to: pasteboard) {
      try copy(text)
      return true
    }
    return false
  }

  /// Adds one separator for collapsed Latin-script cursor boundaries without changing replacements or punctuation attachment.
  static func preparedText(_ text: String, context: TextInsertionContext?) -> String {
    guard let context, !context.hasSelection,
      let precedingCharacter = context.precedingCharacter,
      let firstCharacter = text.first,
      needsSeparator(between: precedingCharacter, and: firstCharacter)
    else {
      return text
    }
    return " " + text
  }

  private static func needsSeparator(between preceding: Character, and incoming: Character) -> Bool
  {
    guard !isWhitespace(preceding), !isWhitespace(incoming) else {
      return false
    }
    guard !isCJK(preceding), !isCJK(incoming) else {
      return false
    }
    let punctuationThatClosesWithoutLeadingSpace = CharacterSet(charactersIn: ".,!?;:%)]}›»”’")
    guard !incoming.unicodeScalars.allSatisfy(punctuationThatClosesWithoutLeadingSpace.contains)
    else {
      return false
    }
    let punctuationThatOpensWithoutTrailingSpace = CharacterSet(charactersIn: "([{‹«“‘")
    return !preceding.unicodeScalars.allSatisfy(punctuationThatOpensWithoutTrailingSpace.contains)
  }

  private static func isWhitespace(_ character: Character) -> Bool {
    character.unicodeScalars.allSatisfy(CharacterSet.whitespacesAndNewlines.contains)
  }

  private static func isCJK(_ character: Character) -> Bool {
    character.unicodeScalars.contains { scalar in
      switch scalar.value {
      case 0x2E80...0x2FFF, 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
        0xAC00...0xD7AF, 0xF900...0xFAFF:
        true
      default:
        false
      }
    }
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
