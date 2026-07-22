// Monitors Fn or Globe modifier changes for global push-to-talk and toggle shortcuts.

import AppKit
import Foundation

/// Owns Fn/Globe shortcut detection, which is exposed as modifier changes instead of a Carbon hotkey.
@MainActor
final class FnHotkeyManager {
    private var localMonitor: Any?
    private var globalEventTap: CFMachPort?
    private var globalEventTapSource: CFRunLoopSource?
    private var isEnabled = false
    private var wasFunctionDown = false
    private var onPressed: (() -> Void)?
    private var onReleased: (() -> Void)?

    func register(
        _ settings: DictationSettings,
        onPressed: @escaping () -> Void,
        onReleased: @escaping () -> Void
    ) {
        self.onPressed = onPressed
        self.onReleased = onReleased
        isEnabled = settings.hotkeyPreset == .fn
        wasFunctionDown = false
        if isEnabled {
            installMonitorsIfNeeded()
        } else {
            removeMonitors()
        }
    }

    /// Installs the global listener after Input Monitoring or Accessibility changes while Vhrase is running.
    func refreshAuthorization() {
        guard isEnabled else {
            return
        }
        installMonitorsIfNeeded()
    }

    private func installMonitorsIfNeeded() {
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                let isFunctionDown = event.isFunctionDown
                Task { @MainActor in
                    self?.handle(isFunctionDown: isFunctionDown)
                }
                return event
            }
        }

        guard globalEventTap == nil else {
            return
        }

        let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, type, event, userInfo in
                guard let userInfo else {
                    return Unmanaged.passUnretained(event)
                }
                let manager = Unmanaged<FnHotkeyManager>
                    .fromOpaque(userInfo)
                    .takeUnretainedValue()
                let shouldReenable = type == .tapDisabledByTimeout || type == .tapDisabledByUserInput
                let isFunctionDown = event.flags.contains(.maskSecondaryFn)
                Task { @MainActor [weak manager] in
                    if shouldReenable {
                        manager?.reenableGlobalEventTap()
                    } else {
                        manager?.handleGlobal(isFunctionDown: isFunctionDown)
                    }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(nil, eventTap, 0) else {
            return
        }

        globalEventTap = eventTap
        globalEventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func removeMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalEventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), globalEventTapSource, .commonModes)
            self.globalEventTapSource = nil
        }
        if let globalEventTap {
            CFMachPortInvalidate(globalEventTap)
            self.globalEventTap = nil
        }
    }

    private func reenableGlobalEventTap() {
        guard let globalEventTap else {
            return
        }
        CGEvent.tapEnable(tap: globalEventTap, enable: true)
    }

    private func handleGlobal(isFunctionDown: Bool) {
        guard !NSApplication.shared.isActive else {
            return
        }
        handle(isFunctionDown: isFunctionDown)
    }

    private func handle(isFunctionDown: Bool) {
        guard isEnabled else {
            return
        }

        guard isFunctionDown != wasFunctionDown else {
            return
        }

        wasFunctionDown = isFunctionDown
        if isFunctionDown {
            onPressed?()
        } else {
            onReleased?()
        }
    }
}

private extension NSEvent {
    var isFunctionDown: Bool {
        modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .contains(.function)
    }
}
