// Detects whether launching Vhrase adds a conventionally visible macOS status-item window.

import CoreGraphics
import Foundation

private struct StatusWindow: Codable {
    let id: Int
    let name: String
    let width: Double
    let height: Double
}

private enum CheckError: Error, CustomStringConvertible {
    case invalidArguments
    case noVisibleStatusItem([StatusWindow])

    var description: String {
        switch self {
        case .invalidArguments:
            "usage: menu-bar-window-check snapshot|assert-visible <snapshot-path>"
        case let .noVisibleStatusItem(windows):
            "Vhrase did not add a visible menu-bar item. New status windows: \(windows)"
        }
    }
}

/// Returns the on-screen status-item windows currently owned by macOS Control Center.
private func currentStatusWindows() -> [StatusWindow] {
    let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
    ) as? [[String: Any]] ?? []

    return windows.compactMap { window in
        guard window[kCGWindowOwnerName as String] as? String == "Control Center",
              window[kCGWindowLayer as String] as? Int == 25,
              let id = window[kCGWindowNumber as String] as? Int,
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let width = bounds["Width"] as? Double,
              let height = bounds["Height"] as? Double else {
            return nil
        }

        return StatusWindow(
            id: id,
            name: window[kCGWindowName as String] as? String ?? "",
            width: width,
            height: height
        )
    }
}

/// Saves the current status-window identities so a later launch can be attributed by difference.
private func saveSnapshot(to url: URL) throws {
    let data = try JSONEncoder().encode(currentStatusWindows())
    try data.write(to: url, options: .atomic)
}

/// Requires a newly created status window wide enough to render a standard menu-bar symbol.
private func assertVisibleStatusItem(since url: URL) throws {
    let prior = try JSONDecoder().decode(
        [StatusWindow].self,
        from: Data(contentsOf: url)
    )
    let priorIDs = Set(prior.map(\.id))
    let created = currentStatusWindows().filter { !priorIDs.contains($0.id) }

    guard created.contains(where: { $0.height >= 20 && $0.width >= 24 }) else {
        throw CheckError.noVisibleStatusItem(created)
    }
}

do {
    guard CommandLine.arguments.count == 3 else {
        throw CheckError.invalidArguments
    }

    let snapshotURL = URL(fileURLWithPath: CommandLine.arguments[2])
    switch CommandLine.arguments[1] {
    case "snapshot":
        try saveSnapshot(to: snapshotURL)
    case "assert-visible":
        try assertVisibleStatusItem(since: snapshotURL)
        print("menu bar item visible")
    default:
        throw CheckError.invalidArguments
    }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
