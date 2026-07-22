// Defines the adaptive visual tokens and destination metadata for Vhrase's main window.

import AppKit
import SwiftUI

enum MainWindowTab: String, CaseIterable, Hashable, Identifiable {
    case dictation
    case customize
    case setup
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dictation:
            "Home"
        case .customize:
            "Writing"
        case .setup:
            "Setup"
        case .history:
            "History"
        }
    }

    var detail: String {
        switch self {
        case .dictation:
            "Record and review"
        case .customize:
            "Providers and cleanup"
        case .setup:
            "Keys and permissions"
        case .history:
            "Saved transcripts"
        }
    }

    var systemImage: String {
        switch self {
        case .dictation:
            "waveform"
        case .customize:
            "slider.horizontal.3"
        case .setup:
            "checkmark.shield"
        case .history:
            "clock.arrow.circlepath"
        }
    }
}

enum AppTheme {
    static let field = Color(nsColor: .controlBackgroundColor)
    static let hairline = Color(nsColor: .separatorColor)
    static let accent = Color.accentColor
    static let sectionCornerRadius: CGFloat = 16
    static let fieldCornerRadius: CGFloat = 10
}

private struct ContentSectionModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: AppTheme.sectionCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.sectionCornerRadius, style: .continuous)
                    .strokeBorder(AppTheme.hairline.opacity(0.65), lineWidth: 1)
            }
    }
}

private struct OperationalSurfaceModifier: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        content
            .padding(22)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.regularMaterial)
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(tint.opacity(0.075))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(tint.opacity(0.24), lineWidth: 1)
            }
            .shadow(color: tint.opacity(0.08), radius: 24, y: 10)
    }
}

extension View {
    func contentSection() -> some View {
        modifier(ContentSectionModifier())
    }

    func operationalSurface(tint: Color) -> some View {
        modifier(OperationalSurfaceModifier(tint: tint))
    }
}
