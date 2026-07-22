// Captures optional screenshot context for transcript adjustment without owning adjustment policy.

import Foundation
import CoreGraphics

/// Captures screenshot context for transcript adjustment using the macOS screen capture boundary.
struct ScreenContext: Sendable {
    private let screencaptureURL = URL(fileURLWithPath: "/usr/sbin/screencapture")

    /// Returns a PNG data URL for the main display, or `nil` when authorization, capture, reading, or setup fails.
    func mainDisplayPNGDataURL() -> String? {
        guard isScreenCaptureAuthorized else {
            return nil
        }

        guard let captureDirectory = temporaryCaptureDirectory() else {
            return nil
        }
        let captureURL = captureDirectory.appendingPathComponent("capture.png")
        defer {
            try? FileManager.default.removeItem(at: captureDirectory)
        }

        let process = Process()
        process.executableURL = screencaptureURL
        process.arguments = [
            "-x",
            "-m",
            captureURL.path,
        ]

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return nil
            }
            let data = try Data(contentsOf: captureURL)
            guard !data.isEmpty else {
                return nil
            }
            return "data:image/png;base64,\(data.base64EncodedString())"
        } catch {
            return nil
        }
    }

    private var isScreenCaptureAuthorized: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Creates a capture-specific directory so every file emitted by `screencapture` shares one cleanup boundary.
    private func temporaryCaptureDirectory() -> URL? {
        guard let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }

        let directory = cacheDirectory
            .appendingPathComponent("Vhrase/Screenshots", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return directory
        } catch {
            return nil
        }
    }
}
