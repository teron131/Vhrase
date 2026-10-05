// Reads, requests, and routes users to macOS privacy permissions required by enabled features.

import AVFoundation
import AppKit
import Foundation
import IOKit.hid

enum AppPermission: String, CaseIterable, Identifiable, Sendable {
  case microphone
  case inputMonitoring
  case screenRecording
  case accessibility

  var id: String { rawValue }

  var title: String {
    switch self {
    case .microphone:
      "Microphone"
    case .inputMonitoring:
      "Input Monitoring"
    case .screenRecording:
      "Screen"
    case .accessibility:
      "Accessibility"
    }
  }

  var systemImage: String {
    switch self {
    case .microphone:
      "mic"
    case .inputMonitoring:
      "keyboard"
    case .screenRecording:
      "rectangle.on.rectangle"
    case .accessibility:
      "cursorarrow.motionlines"
    }
  }
}

enum PermissionState: Equatable, Sendable {
  case granted
  case denied
  case notDetermined
  case unknown

  var title: String {
    switch self {
    case .granted:
      "Ready"
    case .denied:
      "Needs access"
    case .notDetermined:
      "Not allowed yet"
    case .unknown:
      "Unknown"
    }
  }

  var isReady: Bool {
    if case .granted = self {
      return true
    }
    return false
  }
}

struct PermissionSnapshot: Identifiable, Sendable {
  let permission: AppPermission
  let state: PermissionState
  let requestedBefore: Bool

  var id: AppPermission { permission }

  init(
    permission: AppPermission,
    state: PermissionState,
    requestedBefore: Bool = false
  ) {
    self.permission = permission
    self.state = state
    self.requestedBefore = requestedBefore
  }

  /// Names the next step: only an unrequested microphone or input-monitoring permission can still show a native prompt.
  var actionTitle: String {
    guard state == .notDetermined, !requestedBefore else {
      return "Open Settings"
    }
    switch permission {
    case .microphone, .inputMonitoring:
      return "Request Access"
    case .screenRecording, .accessibility:
      return "Open Settings"
    }
  }
}

enum OptionalPermissionRequestStep: Equatable {
  case requestSystemAccess
  case openSettingsIfRequestDenied
}

struct OptionalPermissionRequestPlan {
  static func steps(
    isGranted: Bool,
    requestedBefore: Bool
  ) -> [OptionalPermissionRequestStep] {
    guard !isGranted else {
      return []
    }
    var steps: [OptionalPermissionRequestStep] = [.requestSystemAccess]
    if requestedBefore {
      steps.append(.openSettingsIfRequestDenied)
    }
    return steps
  }
}

@MainActor
final class PermissionManager {
  private let defaults = UserDefaults(suiteName: "local.codex.Vhrase") ?? .standard
  private let accessibilityPromptKey = "permissionPrompt.accessibility"
  private let inputMonitoringPromptKey = "permissionPrompt.inputMonitoring"
  private let screenPromptKey = "permissionPrompt.screenRecording"

  func snapshots() -> [PermissionSnapshot] {
    AppPermission.allCases.map { permission in
      PermissionSnapshot(
        permission: permission,
        state: state(for: permission),
        requestedBefore: requestedBefore(for: permission)
      )
    }
  }

  func request(_ permission: AppPermission) async {
    switch permission {
    case .microphone:
      if state(for: .microphone) == .notDetermined {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
      } else {
        openSettings(for: .microphone)
      }
    case .inputMonitoring:
      requestInputMonitoring()
    case .screenRecording:
      requestScreenRecording()
    case .accessibility:
      requestAccessibility()
    }
  }

  func openSettings(for permission: AppPermission) {
    guard let url = URL(string: settingsURL(for: permission)) else {
      return
    }
    NSWorkspace.shared.open(url)
  }

  private func requestScreenRecording() {
    executeOptionalPermissionRequest(
      .screenRecording,
      promptKey: screenPromptKey,
      requestSystemAccess: CGRequestScreenCaptureAccess
    )
  }

  private func requestInputMonitoring() {
    executeOptionalPermissionRequest(
      .inputMonitoring,
      promptKey: inputMonitoringPromptKey,
      requestSystemAccess: {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
      }
    )
  }

  private func requestAccessibility() {
    executeOptionalPermissionRequest(
      .accessibility,
      promptKey: accessibilityPromptKey
    ) {
      let options =
        [
          "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
      return AXIsProcessTrustedWithOptions(options)
    }
  }

  /// Registers the current signed bundle with macOS before falling back to the matching privacy pane.
  private func executeOptionalPermissionRequest(
    _ permission: AppPermission,
    promptKey: String,
    requestSystemAccess: () -> Bool
  ) {
    let steps = OptionalPermissionRequestPlan.steps(
      isGranted: state(for: permission).isReady,
      requestedBefore: defaults.bool(forKey: promptKey)
    )
    var requestGranted = false
    for step in steps {
      switch step {
      case .requestSystemAccess:
        defaults.set(true, forKey: promptKey)
        requestGranted = requestSystemAccess()
      case .openSettingsIfRequestDenied:
        if !requestGranted {
          openSettings(for: permission)
        }
      }
    }
  }

  private func requestedBefore(for permission: AppPermission) -> Bool {
    switch permission {
    case .microphone:
      AVCaptureDevice.authorizationStatus(for: .audio) != .notDetermined
    case .inputMonitoring:
      defaults.bool(forKey: inputMonitoringPromptKey)
    case .screenRecording:
      defaults.bool(forKey: screenPromptKey)
    case .accessibility:
      defaults.bool(forKey: accessibilityPromptKey)
    }
  }

  private func state(for permission: AppPermission) -> PermissionState {
    switch permission {
    case .microphone:
      switch AVCaptureDevice.authorizationStatus(for: .audio) {
      case .authorized:
        return .granted
      case .denied, .restricted:
        return .denied
      case .notDetermined:
        return .notDetermined
      @unknown default:
        return .unknown
      }
    case .inputMonitoring:
      return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        ? .granted
        : .notDetermined
    case .screenRecording:
      return CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
    case .accessibility:
      return AXIsProcessTrusted() ? .granted : .notDetermined
    }
  }

  private func settingsURL(for permission: AppPermission) -> String {
    switch permission {
    case .microphone:
      "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
    case .inputMonitoring:
      "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
    case .screenRecording:
      "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    case .accessibility:
      "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    }
  }
}
