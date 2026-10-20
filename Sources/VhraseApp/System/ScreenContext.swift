// Captures optional screenshot context for transcript adjustment without owning adjustment policy.

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ScreenContext: Sendable {
  private static let jpegQuality = 0.8
  private let screencaptureURL = URL(fileURLWithPath: "/usr/sbin/screencapture")

  /// Captures the display under the target's front window, or the main display without one; `nil` when authorization or capture fails. Capture runs off the caller's actor because `screencapture` blocks until its process exits.
  func displayJPEGDataURL(
    showing target: FrontmostApp?,
    resolution: ScreenshotResolution
  ) async -> String? {
    await Task.detached(priority: .userInitiated) {
      capture(
        displayBounds: target.flatMap(Self.displayBounds(showing:)),
        maxPixelSize: resolution.maxPixelSize
      )
    }
    .value
  }

  /// Shared by captures and the settings preview, so the preview shows exactly what the model receives; `nil` keeps the image's own size, and a smaller image is never enlarged. JPEG because a 1600-pixel screen of small text is about 0.8 MB, against 1.2 MB as PNG.
  static func downsizedJPEG(from source: CGImageSource, maxPixelSize: Int?) -> Data? {
    let image =
      if let maxPixelSize {
        CGImageSourceCreateThumbnailAtIndex(
          source,
          0,
          [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
          ] as CFDictionary
        )
      } else {
        CGImageSourceCreateImageAtIndex(source, 0, nil)
      }
    guard let image else {
      return nil
    }

    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data,
        UTType.jpeg.identifier as CFString,
        1,
        nil
      )
    else {
      return nil
    }
    CGImageDestinationAddImage(
      destination,
      image,
      [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary
    )
    guard CGImageDestinationFinalize(destination) else {
      return nil
    }
    return data as Data
  }

  private func capture(displayBounds: CGRect?, maxPixelSize: Int?) -> String? {
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
    let displayArgument =
      if let displayBounds {
        "-R\(Int(displayBounds.minX)),\(Int(displayBounds.minY)),\(Int(displayBounds.width)),\(Int(displayBounds.height))"
      } else {
        "-m"
      }
    process.arguments = [
      "-x",
      displayArgument,
      captureURL.path,
    ]

    do {
      try process.run()
      process.waitUntilExit()
      guard process.terminationStatus == 0,
        let source = CGImageSourceCreateWithURL(captureURL as CFURL, nil),
        let data = Self.downsizedJPEG(from: source, maxPixelSize: maxPixelSize)
      else {
        return nil
      }
      return "data:image/jpeg;base64,\(data.base64EncodedString())"
    } catch {
      return nil
    }
  }

  /// Finds the display under the center of the app's frontmost on-screen window, which window bounds reveal without Screen Recording permission.
  /// Window and display bounds share the global top-left coordinate space that `screencapture -R` expects.
  private static func displayBounds(showing target: FrontmostApp) -> CGRect? {
    guard
      let processIdentifier = NSRunningApplication.runningApplications(
        withBundleIdentifier: target.bundleIdentifier
      ).first?.processIdentifier,
      let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
      ) as? [[CFString: Any]],
      let window = windows.first(where: { window in
        window[kCGWindowOwnerPID] as? pid_t == processIdentifier
          && window[kCGWindowLayer] as? Int == 0
      }),
      let windowBounds = window[kCGWindowBounds] as? NSDictionary,
      let frame = CGRect(dictionaryRepresentation: windowBounds)
    else {
      return nil
    }

    var display = CGDirectDisplayID()
    var displayCount: UInt32 = 0
    guard
      CGGetDisplaysWithPoint(CGPoint(x: frame.midX, y: frame.midY), 1, &display, &displayCount)
        == .success,
      displayCount == 1
    else {
      return nil
    }
    return CGDisplayBounds(display)
  }

  private var isScreenCaptureAuthorized: Bool {
    CGPreflightScreenCaptureAccess()
  }

  /// Creates a capture-specific directory so every file emitted by `screencapture` shares one cleanup boundary.
  private func temporaryCaptureDirectory() -> URL? {
    guard
      let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        .first
    else {
      return nil
    }

    let directory =
      cacheDirectory
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
