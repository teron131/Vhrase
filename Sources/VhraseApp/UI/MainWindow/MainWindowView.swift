// Hosts Vhrase's sidebar control center and its selection-driven recording surfaces.

import AppKit
import SwiftUI

struct MainWindowView: View {
  @ObservedObject var appState: AppState
  @Environment(\.accessibilityReduceMotion) var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage("mainWindow.selectedTab") private var selectedTabRawValue = MainWindowTab.dictate
    .rawValue
  @State private var historyBrowsing = HistoryBrowsingState()
  @State var activityRange = ActivityRange.week
  @State var hoveredTab: MainWindowTab?
  @State var selectedCapturePipelineStage = PipelineStage.transcribe
  @Namespace var navigationSelection

  var selectedTab: MainWindowTab {
    get { MainWindowTab(storedRawValue: selectedTabRawValue) }
    nonmutating set { selectedTabRawValue = newValue.rawValue }
  }

  var presentation: DictationPresentation { appState.presentation }

  private var selection: Binding<MainWindowTab> {
    Binding(get: { selectedTab }, set: { selectedTab = $0 })
  }

  var body: some View {
    NavigationSplitView {
      sidebar
        .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 270)
    } detail: {
      content
        .id(selectedTab)
        .transition(tabTransition)
        .navigationTitle(selectedTab.title)
        .hidingToolbarTitle()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VhraseTheme.canvas)
        .overlay(alignment: .top) {
          if !appState.customizationNotice.isEmpty {
            actionNoticeBanner
              .transition(.move(edge: .top).combined(with: .opacity))
              .zIndex(1)
          }
        }
    }
    .frame(minWidth: 1020, minHeight: 680)
    .tint(VhraseTheme.accent)
    .buttonBorderShape(.capsule)
    .animation(
      VhraseMotion.respectingReduceMotion(VhraseMotion.stateSpring, reduceMotion: reduceMotion),
      value: selectedTab
    )
    .onAppear {
      if selectedTabRawValue != selectedTab.rawValue {
        selectedTabRawValue = selectedTab.rawValue
      }
      appState.refreshPermissions()
    }
    .onChange(of: scenePhase) { _, newPhase in
      if newPhase == .active { appState.refreshPermissions() }
    }
    .task(id: appState.customizationNotice) {
      let notice = appState.customizationNotice
      guard !notice.isEmpty else {
        return
      }
      do {
        try await Task.sleep(for: .seconds(5))
      } catch {
        return
      }
      appState.dismissCustomizationNotice(notice)
    }
  }

  private var tabTransition: AnyTransition {
    guard !reduceMotion else {
      return .identity
    }
    return .asymmetric(
      insertion: .move(edge: .trailing).combined(with: .opacity),
      removal: .move(edge: .leading).combined(with: .opacity)
    )
  }

  @ViewBuilder
  private var content: some View {
    switch selectedTab {
    case .dictate:
      DictationView(appState: appState, selectedTab: selection, activityRange: $activityRange)
    case .history:
      HistoryView(appState: appState, browsing: $historyBrowsing)
    case .capture:
      CaptureView(
        appState: appState, selectedTab: selection,
        selectedCapturePipelineStage: $selectedCapturePipelineStage)
    case .output:
      OutputView(appState: appState)
    case .system:
      SystemView(appState: appState, selectedTab: selection)
    }
  }
}

extension View {
  /// Keeps the window title for the Window menu while each page's own header names the destination.
  @ViewBuilder
  fileprivate func hidingToolbarTitle() -> some View {
    if #available(macOS 15.0, *) {
      toolbar(removing: .title)
    } else {
      self
    }
  }
}
