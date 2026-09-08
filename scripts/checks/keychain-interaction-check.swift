// Exercises prompt-free credential operations against a disposable file-based Keychain, never the user's login items.

import Foundation
import Security

@main
struct KeychainInteractionCheck {
  static func main() throws {
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent(".cache/checks/keychain-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let path = directory.appendingPathComponent("fixture.keychain").path
    let password = UUID().uuidString
    var fixture: SecKeychain?
    let createStatus = KeychainInteraction.performWithoutUI {
      password.withCString { bytes in
        SecKeychainCreate(path, UInt32(password.utf8.count), bytes, false, nil, &fixture)
      }
    }
    try require(createStatus == errSecSuccess, "Could not create disposable Keychain", createStatus)
    guard let fixture else { throw failure("Missing test Keychain", errSecInvalidItemRef) }
    defer { _ = KeychainInteraction.performWithoutUI { SecKeychainDelete(fixture) } }

    let originalInteraction = try interactionAllowed()
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: "Vhrase test fixture",
      kSecAttrAccount: "TEST_KEY",
      kSecMatchSearchList: [fixture],
    ]
    var item = query
    item.removeValue(forKey: kSecMatchSearchList)
    item[kSecUseKeychain] = fixture
    item[kSecValueData] = Data("synthetic-test-value".utf8)
    try require(run { SecItemAdd(item as CFDictionary, nil) } == errSecSuccess, "Add failed")

    var read = query
    read[kSecReturnData] = true
    var value: CFTypeRef?
    try require(
      run { SecItemCopyMatching(read as CFDictionary, &value) } == errSecSuccess, "Read failed")
    try require(value as? Data == Data("synthetic-test-value".utf8), "Unexpected fixture content")
    try require(
      run {
        SecItemUpdate(
          query as CFDictionary, [kSecValueData: Data("updated-fixture".utf8)] as CFDictionary)
      } == errSecSuccess, "Update failed")
    try require(
      try interactionAllowed() == originalInteraction, "Interaction policy was not restored")

    try require(SecKeychainLock(fixture) == errSecSuccess, "Could not lock fixture")
    let start = Date()
    let lockedRead = run { SecItemCopyMatching(read as CFDictionary, nil) }
    try requireBlocked(lockedRead, operation: "read")
    let lockedUpdate = run {
      SecItemUpdate(
        query as CFDictionary, [kSecValueData: Data("blocked-update".utf8)] as CFDictionary)
    }
    try requireBlocked(lockedUpdate, operation: "update")
    item[kSecAttrAccount] = "SECOND_TEST_KEY"
    let lockedAdd = run { SecItemAdd(item as CFDictionary, nil) }
    try requireBlocked(lockedAdd, operation: "add")
    try require(Date().timeIntervalSince(start) < 5, "Locked operations stalled")
    try require(
      try interactionAllowed() == originalInteraction, "Failure did not restore interaction policy")

    let unlockStatus = password.withCString { bytes in
      SecKeychainUnlock(fixture, UInt32(password.utf8.count), bytes, true)
    }
    try require(unlockStatus == errSecSuccess, "Could not unlock disposable fixture", unlockStatus)
    try require(run { SecItemDelete(query as CFDictionary) } == errSecSuccess, "Delete failed")
    try require(
      run { SecItemCopyMatching(read as CFDictionary, nil) } == errSecItemNotFound,
      "Delete retained fixture")

    try require(
      SecKeychainSetUserInteractionAllowed(false) == errSecSuccess, "Could not set inherited policy"
    )
    defer { _ = SecKeychainSetUserInteractionAllowed(originalInteraction) }
    try require(
      run { errSecItemNotFound } == errSecItemNotFound, "Operation error was not preserved")
    try require(try !interactionAllowed(), "Disabled inherited policy was changed")

    print("Keychain non-interactive read/add/update/delete and locked-access checks passed")
  }

  /// Runs the production interaction boundary and verifies the callback itself cannot display authentication UI.
  private static func run(_ operation: () -> OSStatus) -> OSStatus {
    KeychainInteraction.performWithoutUI {
      var allowed = DarwinBoolean(true)
      let status = SecKeychainGetUserInteractionAllowed(&allowed)
      guard status == errSecSuccess, !allowed.boolValue else { return errSecInternalComponent }
      return operation()
    }
  }

  private static func interactionAllowed() throws -> Bool {
    var allowed = DarwinBoolean(false)
    let status = SecKeychainGetUserInteractionAllowed(&allowed)
    try require(status == errSecSuccess, "Could not inspect interaction policy", status)
    return allowed.boolValue
  }

  private static func require(
    _ condition: Bool, _ message: String, _ status: OSStatus = errSecInternalComponent
  ) throws {
    if !condition { throw failure(message, status) }
  }

  private static func requireBlocked(_ status: OSStatus, operation: String) throws {
    try require(
      status == errSecInteractionNotAllowed || status == errSecAuthFailed,
      "Locked \(operation) did not fail without UI",
      status
    )
  }

  private static func failure(_ message: String, _ status: OSStatus) -> NSError {
    NSError(
      domain: "VhraseKeychainCheck", code: Int(status),
      userInfo: [NSLocalizedDescriptionKey: "\(message) (\(status))"])
  }
}
