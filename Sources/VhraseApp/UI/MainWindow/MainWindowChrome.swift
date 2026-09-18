// Owns sidebar navigation and notices shared by the main-window destinations.

import AppKit
import SwiftUI

extension MainWindowView {

  var sidebar: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 8) {
            ParrotMark()
              .frame(width: 22, height: 22)
              .accessibilityHidden(true)
            Text("Vhrase")
              .font(VhraseFont.title)
          }
          .padding(.horizontal, 8)
          .padding(.bottom, 12)

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
              HStack(spacing: 10) {
                Image(systemName: tab.systemImage)
                  .font(.callout)
                  .foregroundStyle(
                    selectedTab == tab ? VhraseTheme.accent : VhraseTheme.inkSecondary
                  )
                  .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                  Text(tab.title)
                    .font(.callout.weight(selectedTab == tab ? .semibold : .medium))
                    .lineLimit(1)
                  Text(tab.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                if tab == .dictate, appState.isRecording {
                  Spacer(minLength: 4)
                  Circle()
                    .fill(VhraseTheme.statusRecording)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.vertical, 7)
              .padding(.horizontal, 8)
              .background {
                if selectedTab == tab {
                  RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(VhraseTheme.accentSubtle)
                    .matchedGeometryEffect(id: "navigation-selection", in: navigationSelection)
                } else if hoveredTab == tab {
                  RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                }
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
