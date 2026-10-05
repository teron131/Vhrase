// Owns sidebar navigation and notices shared by the main-window destinations.

import AppKit
import SwiftUI

extension MainWindowView {

  var sidebar: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 2) {
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

          ForEach(MainWindowTab.allCases) { tab in
            Button {
              if tab == .capture, selectedTab == .capture {
                if selectedCapturePipelineStage == .listen, appState.status.canStartRecording {
                  NSApp.activate()
                  appState.audioInputPreview.restart(settings: appState.settings)
                }
              }
              withAnimation(
                VhraseMotion.respectingReduceMotion(
                  VhraseMotion.stateSpring, reduceMotion: reduceMotion)
              ) {
                selectedTab = tab
              }
            } label: {
              HStack(spacing: 9) {
                Image(systemName: tab.systemImage)
                  .font(.system(size: 13, weight: .semibold))
                  .foregroundStyle(selectedTab == tab ? Color.white : VhraseTheme.inkSecondary)
                  .frame(width: 18)
                Text(tab.title)
                  .font(
                    .system(.body, design: .rounded, weight: selectedTab == tab ? .bold : .medium)
                  )
                  .foregroundStyle(selectedTab == tab ? Color.white : Color.primary)
                  .lineLimit(1)

                if tab == .dictate, appState.isRecording {
                  Spacer(minLength: 4)
                  Circle()
                    .fill(selectedTab == tab ? Color.white : VhraseTheme.statusRecording)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                }
              }
              .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
              .padding(.horizontal, 10)
              .background {
                if selectedTab == tab {
                  Capsule()
                    .fill(VhraseTheme.accent)
                    .matchedGeometryEffect(id: "navigation-selection", in: navigationSelection)
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
            .accessibilityValue(selectedTab == tab ? "Selected" : "")
            .accessibilityHint(tab.detail)
          }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }

      sidebarFooter
    }
    .background(.bar)
  }

  var sidebarFooter: some View {
    VStack(alignment: .leading, spacing: 10) {
      Divider()

      Button {
        selectedTab = .system
        appState.refreshPermissions()
      } label: {
        HStack(spacing: 8) {
          Circle()
            .fill(sidebarReadinessColor)
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
          Text(sidebarReadinessTitle)
            .fontWeight(.medium)
            .lineLimit(1)
          Spacer(minLength: 4)
          Image(systemName: "chevron.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
        }
      }
      .buttonStyle(.plain)
      .accessibilityHint("Opens access and readiness settings")

      Button {
        selectedCapturePipelineStage = .trigger
        withAnimation(
          VhraseMotion.respectingReduceMotion(
            VhraseMotion.stateSpring, reduceMotion: reduceMotion)
        ) {
          selectedTab = .capture
        }
      } label: {
        HStack {
          Text("Shortcut")
            .foregroundStyle(.secondary)
          Spacer()
          KeyCap(text: appState.settings.hotkeyDisplay)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("Configure shortcut")
      .accessibilityLabel("Configure shortcut")
      .accessibilityValue(appState.settings.hotkeyDisplay)
      .accessibilityHint("Opens the Trigger stage in Transcription")

    }
    .font(.callout)
    .padding(.horizontal, 14)
    .padding(.bottom, 12)
    .background(.bar)
  }

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

  var sidebarReadinessTitle: String {
    if !presentation.coreRecordingReady {
      return "Needs attention"
    }
    if !presentation.selectedShortcutReady {
      return "Shortcut needs access"
    }
    return "Ready to dictate"
  }

  var sidebarReadinessColor: Color {
    presentation.coreRecordingReady && presentation.selectedShortcutReady
      ? VhraseTheme.statusSuccess
      : VhraseTheme.statusWarning
  }
}
