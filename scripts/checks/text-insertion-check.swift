// Verifies clipboard retention, restoration, and safe failure behavior around text insertion.

import AppKit
import Foundation

@main
struct TextInsertionCheck {
  @MainActor
  static func main() async throws {
    let pasteboard = InMemoryPasteboard()
    pasteboard.clearContents()
    precondition(pasteboard.setString("previous clipboard", forType: .string))

    var pasteEventCount = 0
    let inserter = TextInsertion(
      pasteboard: pasteboard,
      restoreDelay: .zero,
      postPasteShortcut: {
        pasteEventCount += 1
      }
    )

    let retained = try await inserter.paste(
      "transcript",
      keepOnClipboard: false
    )
    precondition(!retained)
    precondition(pasteEventCount == 1)
    precondition(pasteboard.string(forType: .string) == "previous clipboard")

    let explicitlyRetained = try await inserter.paste(
      "kept transcript",
      keepOnClipboard: true
    )
    precondition(explicitlyRetained)
    precondition(pasteEventCount == 2)
    precondition(pasteboard.string(forType: .string) == "kept transcript")

    let changeCountBeforeCancellation = pasteboard.changeCount
    let cancelledPaste = Task { @MainActor in
      withUnsafeCurrentTask { $0?.cancel() }
      return try await inserter.paste("cancelled transcript", keepOnClipboard: true)
    }
    do {
      _ = try await cancelledPaste.value
      preconditionFailure("A cancelled paste must not touch the editor or clipboard.")
    } catch is CancellationError {
      precondition(pasteEventCount == 2)
      precondition(pasteboard.changeCount == changeCountBeforeCancellation)
    }

    var contextAwarePaste = ""
    let contextAwareInserter = TextInsertion(
      pasteboard: pasteboard,
      restoreDelay: .zero,
      postPasteShortcut: {
        contextAwarePaste = pasteboard.string(forType: .string) ?? ""
      }
    )
    let cleanTranscriptRetained = try await contextAwareInserter.paste(
      "Next sentence",
      keepOnClipboard: true,
      context: TextInsertionContext(precedingCharacter: ".", hasSelection: false)
    )
    precondition(cleanTranscriptRetained)
    precondition(contextAwarePaste == " Next sentence")
    precondition(pasteboard.string(forType: .string) == "Next sentence")

    let userCopyInserter = TextInsertion(
      pasteboard: pasteboard,
      restoreDelay: .milliseconds(20),
      postPasteShortcut: {
        Task { @MainActor in
          try? await Task.sleep(for: .milliseconds(1))
          pasteboard.clearContents()
          _ = pasteboard.setString("new user clipboard", forType: .string)
        }
      }
    )
    let userCopyPreserved = try await userCopyInserter.paste(
      "transient transcript",
      keepOnClipboard: false
    )
    precondition(!userCopyPreserved)
    precondition(pasteboard.string(forType: .string) == "new user clipboard")

    let failingInserter = TextInsertion(
      pasteboard: pasteboard,
      restoreDelay: .zero,
      postPasteShortcut: {
        throw PasteEventFailure()
      }
    )
    do {
      _ = try await failingInserter.paste(
        "fallback transcript",
        keepOnClipboard: false
      )
      preconditionFailure("Expected paste event creation to fail.")
    } catch is PasteEventFailure {
      precondition(pasteboard.string(forType: .string) == "fallback transcript")
    }

    precondition(
      TextInsertion.preparedText(
        "Next sentence",
        context: TextInsertionContext(precedingCharacter: ".", hasSelection: false)
      ) == " Next sentence"
    )
    precondition(
      TextInsertion.preparedText(
        "Next sentence",
        context: TextInsertionContext(precedingCharacter: " ", hasSelection: false)
      ) == "Next sentence"
    )
    precondition(
      TextInsertion.preparedText(
        ".",
        context: TextInsertionContext(precedingCharacter: "e", hasSelection: false)
      ) == "."
    )
    precondition(
      TextInsertion.preparedText(
        "下一句",
        context: TextInsertionContext(precedingCharacter: "。", hasSelection: false)
      ) == "下一句"
    )
    precondition(
      TextInsertion.preparedText(
        "replacement",
        context: TextInsertionContext(precedingCharacter: ".", hasSelection: true)
      ) == "replacement"
    )

    print("text insertion ok")
  }
}

private struct PasteEventFailure: Error {}

private final class InMemoryPasteboard: TextPasteboard {
  private(set) var changeCount = 0
  private(set) var pasteboardItems: [NSPasteboardItem]?

  @discardableResult
  func clearContents() -> Int {
    pasteboardItems = []
    changeCount += 1
    return changeCount
  }

  func setString(
    _ string: String,
    forType dataType: NSPasteboard.PasteboardType
  ) -> Bool {
    let item = NSPasteboardItem()
    item.setString(string, forType: dataType)
    pasteboardItems = [item]
    changeCount += 1
    return true
  }

  func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool {
    pasteboardItems = objects.compactMap { $0 as? NSPasteboardItem }
    changeCount += 1
    return pasteboardItems?.count == objects.count
  }

  func string(forType dataType: NSPasteboard.PasteboardType) -> String? {
    pasteboardItems?.first?.string(forType: dataType)
  }
}
