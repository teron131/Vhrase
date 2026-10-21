// Captures and revalidates editable text in the focused macOS accessibility element before replacement, and asks Electron apps to publish that text so the cursor can be read.

import AppKit
import ApplicationServices
import Foundation

@MainActor
struct FocusedTextTarget {
  let app: FrontmostApp
  let text: String

  private let element: AXUIElement
  private let originalSelection: CFRange
  private let replacementRange: CFRange
  private let replacesWholeField: Bool

  init(
    app: FrontmostApp,
    text: String,
    element: AXUIElement,
    originalSelection: CFRange,
    replacementRange: CFRange,
    replacesWholeField: Bool
  ) {
    self.app = app
    self.text = text
    self.element = element
    self.originalSelection = originalSelection
    self.replacementRange = replacementRange
    self.replacesWholeField = replacesWholeField
  }

  /// Selects the original source only when focus, selection, and content still match the captured request.
  func prepareReplacement() throws {
    let service = FocusedTextService()
    guard let focusedElement = service.focusedElement(), CFEqual(focusedElement, element) else {
      throw FocusedTextError.targetChanged
    }
    guard let currentSelection = service.selectedRange(of: element),
      currentSelection.location == originalSelection.location,
      currentSelection.length == originalSelection.length
    else {
      throw FocusedTextError.targetChanged
    }

    if replacesWholeField {
      guard service.stringAttribute(kAXValueAttribute as CFString, of: element) == text else {
        throw FocusedTextError.targetChanged
      }
    } else {
      guard service.stringAttribute(kAXSelectedTextAttribute as CFString, of: element) == text
      else {
        throw FocusedTextError.targetChanged
      }
    }

    try service.setSelectedRange(replacementRange, on: element)
  }
}

@MainActor
struct FocusedTextService {
  static let maximumSourceLength = 12_000

  /// Captures selected text first and otherwise targets the entire focused editable field.
  func capture() throws -> FocusedTextTarget {
    guard AXIsProcessTrusted() else {
      throw FocusedTextError.accessibilityUnavailable
    }
    guard let application = NSWorkspace.shared.frontmostApplication,
      let bundleIdentifier = application.bundleIdentifier,
      !bundleIdentifier.isEmpty,
      let element = focusedElement()
    else {
      throw FocusedTextError.noEditableText
    }

    let subrole = stringAttribute(kAXSubroleAttribute as CFString, of: element)
    guard subrole != (kAXSecureTextFieldSubrole as String) else {
      throw FocusedTextError.secureField
    }
    guard let selection = selectedRange(of: element) else {
      throw FocusedTextError.noEditableText
    }
    var rangeSettable = DarwinBoolean(false)
    guard
      AXUIElementIsAttributeSettable(
        element,
        kAXSelectedTextRangeAttribute as CFString,
        &rangeSettable
      ) == .success, rangeSettable.boolValue
    else {
      throw FocusedTextError.noEditableText
    }

    let source: String
    let replacementRange: CFRange
    let replacesWholeField: Bool
    if selection.length > 0,
      let selectedText = stringAttribute(kAXSelectedTextAttribute as CFString, of: element)
    {
      source = selectedText
      replacementRange = selection
      replacesWholeField = false
    } else if let value = stringAttribute(kAXValueAttribute as CFString, of: element) {
      source = value
      replacementRange = CFRange(location: 0, length: (value as NSString).length)
      replacesWholeField = true
    } else {
      throw FocusedTextError.noEditableText
    }

    guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw FocusedTextError.emptyText
    }
    guard (source as NSString).length <= Self.maximumSourceLength else {
      throw FocusedTextError.textTooLong(maximum: Self.maximumSourceLength)
    }

    return FocusedTextTarget(
      app: FrontmostApp(
        name: application.localizedName ?? "Unknown",
        bundleIdentifier: bundleIdentifier
      ),
      text: source,
      element: element,
      originalSelection: selection,
      replacementRange: replacementRange,
      replacesWholeField: replacesWholeField
    )
  }

  /// Electron apps such as Claude and Codex publish their text to Accessibility only once a client asks, and keep publishing until they quit; other apps ignore the request.
  /// The app builds that text in the background, so ask when recording starts rather than when the cursor is read.
  func exposeText(in app: FrontmostApp) {
    guard
      let application = NSRunningApplication.runningApplications(
        withBundleIdentifier: app.bundleIdentifier
      ).first
    else {
      return
    }
    _ = AXUIElementSetAttributeValue(
      AXUIElementCreateApplication(application.processIdentifier),
      "AXManualAccessibility" as CFString,
      kCFBooleanTrue
    )
  }

  /// Reads only the collapsed cursor boundary needed to separate consecutive dictations safely.
  func insertionContext() -> TextInsertionContext? {
    guard AXIsProcessTrusted(), let element = focusedElement() else {
      return nil
    }
    let subrole = stringAttribute(kAXSubroleAttribute as CFString, of: element)
    guard subrole != (kAXSecureTextFieldSubrole as String),
      let selection = selectedRange(of: element)
    else {
      return nil
    }
    guard selection.length == 0 else {
      return TextInsertionContext(precedingCharacter: nil, hasSelection: true)
    }
    guard selection.location > 0 else {
      return TextInsertionContext(precedingCharacter: nil, hasSelection: false)
    }

    let precedingCharacter = precedingCharacter(
      element: element,
      cursorLocation: selection.location
    )
    return TextInsertionContext(
      precedingCharacter: precedingCharacter,
      hasSelection: false
    )
  }

  func focusedElement() -> AXUIElement? {
    let system = AXUIElementCreateSystemWide()
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        system,
        kAXFocusedUIElementAttribute as CFString,
        &value
      ) == .success, let value
    else {
      return nil
    }
    return unsafeDowncast(value, to: AXUIElement.self)
  }

  func stringAttribute(_ attribute: CFString, of element: AXUIElement) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
      return nil
    }
    return value as? String
  }

  func selectedRange(of element: AXUIElement) -> CFRange? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        element,
        kAXSelectedTextRangeAttribute as CFString,
        &value
      ) == .success, let value, CFGetTypeID(value) == AXValueGetTypeID()
    else {
      return nil
    }
    let rangeValue = unsafeDowncast(value, to: AXValue.self)
    var range = CFRange()
    guard AXValueGetValue(rangeValue, .cfRange, &range), range.location >= 0, range.length >= 0
    else {
      return nil
    }
    return range
  }

  func setSelectedRange(_ range: CFRange, on element: AXUIElement) throws {
    var mutableRange = range
    guard let value = AXValueCreate(.cfRange, &mutableRange),
      AXUIElementSetAttributeValue(
        element,
        kAXSelectedTextRangeAttribute as CFString,
        value
      ) == .success
    else {
      throw FocusedTextError.targetChanged
    }
  }

  private func precedingCharacter(element: AXUIElement, cursorLocation: Int) -> Character? {
    if let value = stringAttribute(kAXValueAttribute as CFString, of: element) {
      let text = value as NSString
      guard cursorLocation <= text.length else {
        return nil
      }
      let range = text.rangeOfComposedCharacterSequence(at: cursorLocation - 1)
      return text.substring(with: range).first
    }

    // Two UTF-16 units, so a preceding emoji or other surrogate pair arrives whole.
    var range = CFRange(location: max(0, cursorLocation - 2), length: min(2, cursorLocation))
    guard let rangeValue = AXValueCreate(.cfRange, &range) else {
      return nil
    }
    var value: CFTypeRef?
    guard
      AXUIElementCopyParameterizedAttributeValue(
        element,
        kAXStringForRangeParameterizedAttribute as CFString,
        rangeValue,
        &value
      ) == .success,
      let text = value as? String
    else {
      return nil
    }
    return text.last
  }
}

enum FocusedTextError: LocalizedError {
  case accessibilityUnavailable
  case emptyText
  case noEditableText
  case secureField
  case targetChanged
  case textTooLong(maximum: Int)

  var errorDescription: String? {
    switch self {
    case .accessibilityUnavailable:
      "Grant Accessibility permission before polishing text."
    case .emptyText:
      "The focused field has no text to polish."
    case .noEditableText:
      "Focus an editable text field or select text before polishing."
    case .secureField:
      "Vhrase does not read or polish secure text fields."
    case .targetChanged:
      "The focused text changed while Vhrase was polishing it. Nothing was replaced."
    case .textTooLong(let maximum):
      "Text polishing supports up to \(maximum) characters at a time."
    }
  }
}
