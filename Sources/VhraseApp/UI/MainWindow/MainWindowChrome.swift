// Owns the sidebar, which draws the dictation stages as one route above the style sheet they read, shows each destination's live state, and keeps the theme and the System gear in its bottom corner; also the notice banner the destinations share.

import AVFoundation
import AppKit
import SwiftUI

/// Lists every destination with what it is set to now; the stages hang on one dotted line in the order speech travels, and a stage whose page holds unfinished setup carries a badge.
struct MainWindowSidebar: View {
  @ObservedObject var appState: AppState
  @Binding var selection: MainWindowTab
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hoveredTab: MainWindowTab?
  @State private var microphoneName = ""
  @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.system
  @Namespace private var selectionNamespace

  /// Every row has the same height so the route's line runs exactly from the first stage's mark to the last.
  private static let rowHeight: CGFloat = 42
  private static let markSize: CGFloat = 26
  private static let rowPadding: CGFloat = 10

  var body: some View {
    // One projection per render: every row's summary and badge read the same readiness.
    let presentation = appState.presentation
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 2) {
          wordmark
          row(.dictation, presentation)
          row(.history, presentation)
          sectionLabel("Machinery")
          route(presentation)
          sectionLabel("Style sheet")
          row(.vocabulary, presentation)
          row(.writing, presentation)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }

      // The theme and System apply to the whole app, so they stay in reach from every page; the gear sits at the far end so it never reads as a fourth theme.
      HStack(spacing: 8) {
        PillPicker(
          title: "Theme", selection: $appearance, options: AppearancePreference.allCases,
          label: \.title, systemImage: \.systemImage
        )
        Spacer(minLength: 8)
        systemButton(presentation)
      }
      .padding(12)
    }
    .background(.bar)
    .onChange(of: appearance) { _, choice in
      choice.apply()
    }
    .task(id: appState.settings.inputDeviceUID) { refreshMicrophoneName() }
    .onReceive(
      NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification)
    ) { _ in refreshMicrophoneName() }
    .onReceive(
      NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification)
    ) { _ in refreshMicrophoneName() }
  }

  private var wordmark: some View {
    HStack(spacing: 8) {
      ParrotMark()
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
      Text("Vhrase")
        .font(.system(.title2, design: .rounded, weight: .heavy))
    }
    .padding(.horizontal, 8)
    .padding(.top, 4)
    .padding(.bottom, 14)
  }

  /// Names the tier the rows below it share in small tracked capitals, starting at the marks' edge so it heads the whole group rather than reading as another row title.
  private func sectionLabel(_ title: String) -> some View {
    Text(title)
      .font(.system(.subheadline, design: .rounded, weight: .heavy))
      .textCase(.uppercase)
      .tracking(0.8)
      .foregroundStyle(VhraseTheme.inkSecondary)
      .padding(.leading, Self.rowPadding)
      .padding(.top, 14)
      .padding(.bottom, 4)
      .accessibilityAddTraits(.isHeader)
  }

  /// Joins the stages with one dotted line so they read as the route a dictation travels.
  private func route(_ presentation: DictationPresentation) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(MainWindowTab.route) { tab in
        row(tab, presentation)
      }
    }
    .background(alignment: .leading) {
      RouteLine()
        .stroke(
          Color.primary.opacity(0.24),
          style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 4])
        )
        .frame(width: 2)
        .padding(.vertical, Self.rowHeight / 2)
        .padding(.leading, Self.rowPadding + Self.markSize / 2 - 1)
        .accessibilityHidden(true)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Machinery")
  }

  private func row(_ tab: MainWindowTab, _ presentation: DictationPresentation) -> some View {
    let isSelected = selection == tab
    let summary = summary(tab, presentation)
    let needsAttention = needsAttention(tab, presentation)
    return Button {
      select(tab)
    } label: {
      HStack(spacing: 10) {
        mark(tab, isSelected: isSelected, needsAttention: needsAttention)

        VStack(alignment: .leading, spacing: 1) {
          Text(tab.title)
            .font(.system(.body, design: .rounded, weight: isSelected ? .bold : .medium))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
          Text(summary)
            .font(.caption)
            .foregroundStyle(isSelected ? Color.white.opacity(0.85) : VhraseTheme.inkSecondary)
        }
        .lineLimit(1)

        if tab == .dictation, appState.isRecording {
          Spacer(minLength: 4)
          Circle()
            .fill(isSelected ? Color.white : VhraseTheme.statusRecording)
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
        }
      }
      .padding(.horizontal, Self.rowPadding)
      .frame(
        maxWidth: .infinity, minHeight: Self.rowHeight, maxHeight: Self.rowHeight,
        alignment: .leading
      )
      .background {
        if isSelected {
          Capsule()
            .fill(VhraseTheme.accent)
            .matchedGeometryEffect(id: "navigation-selection", in: selectionNamespace)
        } else if hoveredTab == tab {
          Capsule()
            .fill(Color.primary.opacity(0.06))
        }
      }
      .contentShape(Capsule())
    }
    .buttonStyle(PressableButtonStyle(pressedScale: 0.96))
    .onHover { isHovered in
      if isHovered {
        hoveredTab = tab
      } else if hoveredTab == tab {
        hoveredTab = nil
      }
    }
    .animation(
      VhraseMotion.respectingReduceMotion(VhraseMotion.settle, reduceMotion: reduceMotion),
      value: hoveredTab
    )
    .accessibilityLabel(tab.title)
    .accessibilityValue(needsAttention ? "\(summary), needs attention" : summary)
    .accessibilityHint(tab.detail)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  /// Route stages sit in circular stations on the line, white inside the selected pill; other destinations keep a bare symbol.
  @ViewBuilder
  private func mark(_ tab: MainWindowTab, isSelected: Bool, needsAttention: Bool) -> some View {
    let symbol = Image(systemName: tab.systemImage)
    if MainWindowTab.route.contains(tab) {
      let stationFill = isSelected ? Color.white : VhraseTheme.card
      symbol
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(isSelected ? VhraseTheme.accent : VhraseTheme.inkSecondary)
        .frame(width: Self.markSize, height: Self.markSize)
        .background(Circle().fill(stationFill))
        .overlay {
          if !isSelected {
            Circle().strokeBorder(VhraseTheme.hairline, lineWidth: 1)
          }
        }
        .overlay(alignment: .topTrailing) {
          if needsAttention {
            attentionDot
              .overlay { Circle().strokeBorder(stationFill, lineWidth: 1.5) }
              .offset(x: 2, y: -2)
          }
        }
        .accessibilityHidden(true)
    } else {
      symbol
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(isSelected ? Color.white : VhraseTheme.inkSecondary)
        .frame(width: Self.markSize, height: Self.markSize)
        .overlay(alignment: .topTrailing) {
          if needsAttention {
            attentionDot
          }
        }
        .accessibilityHidden(true)
    }
  }

  /// The amber badge for unfinished setup, shared by stage stations, bare symbols, and the System gear.
  private var attentionDot: some View {
    Circle()
      .fill(VhraseTheme.statusWarning)
      .frame(width: 10, height: 10)
  }

  /// What each destination is set to now, so the sidebar doubles as a summary of the whole configuration.
  private func summary(_ tab: MainWindowTab, _ presentation: DictationPresentation) -> String {
    let settings = appState.settings
    switch tab {
    case .dictation:
      return presentation.displayStatusTitle
    case .history:
      return appState.savesTranscriptHistory ? "\(appState.history.count) saved" : "Saving off"
    case .shortcut:
      return settings.hotkeyDisplay
    case .microphone:
      return microphoneName
    case .transcription:
      return "\(settings.provider.title) · \(settings.transcriptionModeTitle)"
    case .refinement:
      guard settings.adjustWithLLM else { return "Raw transcripts" }
      let model = settings.adjustmentModel.split(separator: "/").last.map(String.init) ?? ""
      return model.isEmpty ? "No model chosen" : model
    case .delivery:
      if !presentation.permissionIsReady(.accessibility) { return "Clipboard only" }
      return settings.keepTranscriptOnClipboard ? "Paste and keep a copy" : "Paste into your app"
    case .vocabulary:
      let count = settings.keytermList.count
      return count == 1 ? "1 term" : "\(count) terms"
    case .writing:
      return PolishPreset.matching(settings.polishPreferences)?.title ?? "Custom"
    case .system:
      if !presentation.coreRecordingReady { return "Needs attention" }
      if !presentation.selectedShortcutReady { return "Shortcut needs access" }
      return "Ready to dictate"
    }
  }

  /// Badges the stage whose page shows the unfinished setup and its fix, so the route points at where to go.
  private func needsAttention(_ tab: MainWindowTab, _ presentation: DictationPresentation) -> Bool {
    let settings = appState.settings
    switch tab {
    case .shortcut:
      return !presentation.selectedShortcutReady
    case .microphone:
      return !presentation.permissionIsReady(.microphone)
    case .transcription:
      return presentation.providerReadiness != .ready
        || (presentation.transcriptionConfigurationIssue != nil
          && presentation.transcriptionConfigurationIssue != presentation.vocabularyIssue)
    case .refinement:
      guard settings.adjustWithLLM else { return false }
      return appState.credentials.effectiveValue(.llmAPIKey).isEmpty
        || settings.adjustmentModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || (settings.includeScreenshot && !presentation.permissionIsReady(.screenRecording))
    case .delivery:
      return !presentation.permissionIsReady(.accessibility)
    case .vocabulary:
      return presentation.vocabularyIssue != nil
    case .system:
      return !presentation.coreRecordingReady || !presentation.selectedShortcutReady
    case .dictation, .history, .writing:
      return false
    }
  }

  /// System is the familiar settings gear rather than a row, and its dot marks unfinished setup the way the stage badges do.
  private func systemButton(_ presentation: DictationPresentation) -> some View {
    let isSelected = selection == .system
    let isHovered = hoveredTab == .system
    return Button {
      select(.system)
    } label: {
      Image(systemName: MainWindowTab.system.systemImage)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(isSelected ? Color.white : VhraseTheme.inkSecondary)
        .frame(width: 32, height: 32)
        .background(
          Circle().fill(
            isSelected
              ? VhraseTheme.accent : (isHovered ? Color.primary.opacity(0.1) : VhraseTheme.field)
          )
        )
        .overlay(alignment: .topTrailing) {
          if needsAttention(.system, presentation) {
            attentionDot
              .offset(x: 1, y: -1)
          }
        }
        .contentShape(Circle())
    }
    .buttonStyle(PressableButtonStyle(pressedScale: 0.92))
    .onHover { isHovering in
      if isHovering {
        hoveredTab = .system
      } else if hoveredTab == .system {
        hoveredTab = nil
      }
    }
    .help(MainWindowTab.system.title)
    .accessibilityLabel(MainWindowTab.system.title)
    .accessibilityValue(summary(.system, presentation))
    .accessibilityHint(MainWindowTab.system.detail)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  private func select(_ tab: MainWindowTab) {
    // Choosing Microphone again reacquires the preview after another app has used the microphone.
    if tab == .microphone, selection == .microphone, appState.canStartRecording {
      NSApp.activate()
      appState.audioInputPreview.restart(settings: appState.settings)
    }
    if tab == .system {
      appState.refreshPermissions()
    }
    withAnimation(
      VhraseMotion.respectingReduceMotion(VhraseMotion.stateSpring, reduceMotion: reduceMotion)
    ) {
      selection = tab
    }
  }

  /// Names the saved microphone, or says the Mac's input is followed; an unplugged choice says so rather than naming another device.
  private func refreshMicrophoneName() {
    let uid = appState.settings.inputDeviceUID
    guard !uid.isEmpty else {
      microphoneName = "System default"
      return
    }
    microphoneName =
      (try? AudioInputDevice.available())?.first(where: { $0.id == uid })?.name
      ?? "Microphone disconnected"
  }
}

/// A vertical center line for the route's dotted connector.
private struct RouteLine: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.midX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
    return path
  }
}

extension MainWindowView {
  var actionNoticeBanner: some View {
    HStack(spacing: 9) {
      Image(systemName: "info.circle.fill")
        .foregroundStyle(VhraseTheme.accent)
        .accessibilityHidden(true)

      Text(appState.customizationNotice)
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)

      Button {
        appState.dismissCustomizationNotice(appState.customizationNotice)
      } label: {
        Image(systemName: "xmark")
      }
      .buttonStyle(.plain)
      .help("Dismiss")
      .accessibilityLabel("Dismiss notification")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(.bar)
    .overlay(alignment: .bottom) {
      Divider()
    }
    .accessibilityElement(children: .contain)
  }
}
