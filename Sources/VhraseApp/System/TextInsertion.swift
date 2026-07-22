// Copies finalized text and emits paste only after the recorded target has been restored.

import AppKit
import Foundation

struct TextInsertion {
    /// Replaces the general pasteboard with finalized text and reports a failed pasteboard write.
    func copy(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw TextInsertionError.copyFailed
        }
    }

    /// Posts Command-V after AppContext has confirmed the intended app owns focus.
    func paste() throws {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            throw TextInsertionError.pasteEventUnavailable
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
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
