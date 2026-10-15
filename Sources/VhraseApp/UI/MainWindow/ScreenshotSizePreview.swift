// Simulates what a screenshot size does to small screen text, independent of this Mac's own display settings.

import AppKit
import ImageIO
import SwiftUI

/// Shows sample text as a Retina screen draws it beside the same text after the capture's real downsizing step.
/// The reference is a fixed 3456 × 2234 Retina screenshot, so the simulation reads the same on any display.
struct ScreenshotSizePreview: View {
  let resolution: ScreenshotResolution
  @Environment(\.colorScheme) private var colorScheme

  private static let zoom: CGFloat = 1.4
  /// OpenAI's patch-based vision models bill 32-pixel squares at 1.2 tokens each.
  private static let openAIPatchSize = 32
  private static let openAITokensPerPatch = 1.2

  var body: some View {
    let sample = ScreenshotSample.shared(dark: colorScheme == .dark)
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 12) {
        panel("Retina screen", image: sample.screen, sample: sample)
        panel(sentTitle, image: sample.sent(at: resolution), sample: sample)
      }
      Text(summary)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Screenshot size preview")
    .accessibilityValue(summary)
  }

  private var sentTitle: String {
    resolution == .original ? "Sent at full size" : "Sent at \(resolution.title) px"
  }

  /// Converts the reference screenshot at this size into the two facts the slider trades: text size and OpenAI image tokens.
  private var summary: String {
    let reference = ScreenshotSample.referenceSize
    let scale = ScreenshotSample.scale(for: resolution)
    let width = Int((reference.width * scale).rounded())
    let height = Int((reference.height * scale).rounded())
    let bodyPointSize = ScreenshotSample.bodyPointSize
    let textPixels = Double(bodyPointSize * ScreenshotSample.retinaScale * scale)
      .formatted(.number.precision(.fractionLength(0...1)))
    let patches = patchCount(width) * patchCount(height)
    let tokens = Int((Double(patches) * Self.openAITokensPerPatch).rounded(.up))
    return
      "Simulated on a \(Int(reference.width)) × \(Int(reference.height)) Retina screenshot sent at \(width) × \(height): \(Int(bodyPointSize)) pt text lands at about \(textPixels) px, and OpenAI counts about \(tokens.formatted()) image tokens."
  }

  private func patchCount(_ pixels: Int) -> Int {
    (pixels + Self.openAIPatchSize - 1) / Self.openAIPatchSize
  }

  /// Fills its half of the row with the sample's own background, so a wide row reads as more of the same screen.
  /// The sample shrinks with the row instead of fixing its width, because a page wider than the detail column pushes the whole window, sidebar included, sideways.
  private func panel(_ title: String, image: NSImage?, sample: ScreenshotSample) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Group {
        if let image {
          Image(nsImage: image)
            .resizable()
            .interpolation(.high)
        } else {
          Color.clear
        }
      }
      .aspectRatio(sample.size, contentMode: .fit)
      .frame(maxWidth: sample.size.width * Self.zoom, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(nsColor: sample.background))
      .clipShape(RoundedRectangle(cornerRadius: VhraseTheme.fieldCornerRadius, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: VhraseTheme.fieldCornerRadius, style: .continuous)
          .strokeBorder(VhraseTheme.hairline)
      }
    }
  }
}

/// Renders the sample once per appearance and caches each downsized version, so settings changes elsewhere never redraw it.
@MainActor
private final class ScreenshotSample {
  static let referenceSize = CGSize(width: 3456, height: 2234)
  static let retinaScale: CGFloat = 2
  static let bodyPointSize: CGFloat = 13

  private static var samples: [Bool: ScreenshotSample] = [:]
  private static let padding: CGFloat = 10
  private static let lines: [(text: String, pointSize: CGFloat, secondary: Bool)] = [
    ("Siobhán Ní Dhuibhir approved VHR-4821", bodyPointSize, false),
    ("Wojciech Szczęsny-Okafor · INC-73914 · #oncall", 11, true),
  ]

  let screen: NSImage?
  let size: CGSize
  let background: NSColor
  private let png: Data?
  private var sentImages: [ScreenshotResolution: NSImage] = [:]

  static func shared(dark: Bool) -> ScreenshotSample {
    if let sample = samples[dark] {
      return sample
    }
    let sample = ScreenshotSample(dark: dark)
    samples[dark] = sample
    return sample
  }

  /// The fraction of the reference screenshot's pixels kept at this size.
  static func scale(for resolution: ScreenshotResolution) -> CGFloat {
    guard let maxPixelSize = resolution.maxPixelSize else {
      return 1
    }
    return min(1, CGFloat(maxPixelSize) / referenceSize.width)
  }

  /// Downsizes the Retina sample by the same fraction the reference screenshot loses, through the capture's own JPEG step.
  func sent(at resolution: ScreenshotResolution) -> NSImage? {
    if let image = sentImages[resolution] {
      return image
    }
    let maxPixelSize: Int? =
      resolution == .original
      ? nil : Int((size.width * Self.retinaScale * Self.scale(for: resolution)).rounded())
    guard let png,
      let source = CGImageSourceCreateWithData(png as CFData, nil),
      let data = ScreenContext.downsizedJPEG(from: source, maxPixelSize: maxPixelSize),
      let image = NSImage(data: data)
    else {
      return nil
    }
    sentImages[resolution] = image
    return image
  }

  private init(dark: Bool) {
    let fonts = Self.lines.map { NSFont.systemFont(ofSize: $0.pointSize) }
    let widths = zip(Self.lines, fonts).map { line, font in
      (line.text as NSString).size(withAttributes: [.font: font]).width
    }
    let lineHeights = fonts.map { ceil($0.ascender - $0.descender + $0.leading) + 4 }
    size = CGSize(
      width: ceil((widths.max() ?? 0) + Self.padding * 2),
      height: ceil(lineHeights.reduce(0, +) + Self.padding * 2)
    )

    background = dark ? NSColor(white: 0.12, alpha: 1) : NSColor.white
    let primary = dark ? NSColor(white: 0.93, alpha: 1) : NSColor(white: 0.11, alpha: 1)
    let secondary = dark ? NSColor(white: 0.62, alpha: 1) : NSColor(white: 0.42, alpha: 1)
    guard
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width * Self.retinaScale),
        pixelsHigh: Int(size.height * Self.retinaScale),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      )
    else {
      screen = nil
      png = nil
      return
    }
    bitmap.size = size

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    background.setFill()
    NSRect(origin: .zero, size: size).fill()
    var top = Self.padding
    for (line, (font, height)) in zip(Self.lines, zip(fonts, lineHeights)) {
      let color = line.secondary ? secondary : primary
      (line.text as NSString).draw(
        at: NSPoint(x: Self.padding, y: size.height - top - height + 2),
        withAttributes: [.font: font, .foregroundColor: color]
      )
      top += height
    }
    NSGraphicsContext.restoreGraphicsState()

    let image = NSImage(size: size)
    image.addRepresentation(bitmap)
    screen = image
    png = bitmap.representation(using: .png, properties: [:])
  }
}
