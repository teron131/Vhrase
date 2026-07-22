// Reads, requests, and routes users to macOS privacy permissions required by enabled features.

import AppKit
import AVFoundation
import Foundation

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
            "Ask"
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

    var displayTitle: String {
        if state == .notDetermined {
            if requestedBefore {
                return "Open Settings"
            }
            switch permission {
            case .microphone, .inputMonitoring:
                return state.title
            case .screenRecording, .accessibility:
                return "Open Settings"
            }
        }
        return state.title
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

    /// Requests only the core microphone permission; optional permissions are requested when their features are enabled.
    func setupPermissions() async {
        if state(for: .microphone) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
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
            requestInputMonitoringOnce()
        case .screenRecording:
            requestScreenRecordingOnce()
        case .accessibility:
            requestAccessibilityOnce()
        }
    }

    func openSettings(for permission: AppPermission) {
        guard let url = URL(string: settingsURL(for: permission)) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func requestScreenRecordingOnce() {
        guard state(for: .screenRecording) != .granted else {
            return
        }

        guard !defaults.bool(forKey: screenPromptKey) else {
            openSettings(for: .screenRecording)
            return
        }

        defaults.set(true, forKey: screenPromptKey)
        _ = CGRequestScreenCaptureAccess()
    }

    private func requestInputMonitoringOnce() {
        guard state(for: .inputMonitoring) != .granted else {
            return
        }

        guard !defaults.bool(forKey: inputMonitoringPromptKey) else {
            openSettings(for: .inputMonitoring)
            return
        }

        defaults.set(true, forKey: inputMonitoringPromptKey)
        _ = CGRequestListenEventAccess()
    }

    private func requestAccessibilityOnce() {
        guard state(for: .accessibility) != .granted else {
            return
        }

        guard !defaults.bool(forKey: accessibilityPromptKey) else {
            openSettings(for: .accessibility)
            return
        }

        defaults.set(true, forKey: accessibilityPromptKey)
        let options = [
            "AXTrustedCheckOptionPrompt": true,
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
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
            return CGPreflightListenEventAccess() ? .granted : .notDetermined
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
