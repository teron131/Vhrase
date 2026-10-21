// Hosts Vhrase's sidebar route and the selected destination under the notice banner pages share, and carries a page's request to open a System credential field.

import AppKit
import SwiftUI

struct MainWindowView: View {
  @ObservedObject var appState: AppState
  @Environment(\.accessibilityReduceMotion) var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage("mainWindow.selectedTab") private var selectedTabRawValue = MainWindowTab.dictation
    .rawValue
  @State private var historyBrowsing = HistoryBrowsingState()
  @State private var activityRange = ActivityRange.week
  @State private var credentialRequest: SecretKey?

  var selectedTab: MainWindowTab {
    get { MainWindowTab(storedRawValue: selectedTabRawValue) }
    nonmutating set { selectedTabRawValue = newValue.rawValue }
  }

  private var selection: Binding<MainWindowTab> {
    Binding(get: { selectedTab }, set: { selectedTab = $0 })
  }

  private var navigation: MainWindowNavigation {
    MainWindowNavigation(selection: selection, credentialRequest: $credentialRequest)
  }

  var body: some View {
    NavigationSplitView {
      MainWindowSidebar(appState: appState, selection: selection)
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
          if !appState.notice.isEmpty {
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
    .task(id: appState.notice) {
      let notice = appState.notice
      guard !notice.isEmpty else {
        return
      }
      do {
        try await Task.sleep(for: .seconds(5))
      } catch {
        return
      }
      appState.dismissNotice(notice)
    }
  }

  private var actionNoticeBanner: some View {
    HStack(spacing: 9) {
      Image(systemName: "info.circle.fill")
        .foregroundStyle(VhraseTheme.accent)
        .accessibilityHidden(true)

      Text(appState.notice)
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)

      Button {
        appState.dismissNotice(appState.notice)
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
    case .dictation:
      DictationView(appState: appState, navigation: navigation, activityRange: $activityRange)
    case .history:
      HistoryView(appState: appState, browsing: $historyBrowsing)
    case .shortcut:
      ShortcutView(appState: appState)
    case .microphone:
      MicrophoneView(appState: appState)
    case .transcription:
      TranscriptionView(appState: appState, navigation: navigation)
    case .refinement:
      RefinementView(appState: appState, navigation: navigation)
    case .delivery:
      DeliveryView(appState: appState, navigation: navigation)
    case .vocabulary:
      VocabularyView(appState: appState, navigation: navigation)
    case .writing:
      WritingView(appState: appState)
    case .system:
      SystemView(appState: appState, navigation: navigation, credentialRequest: $credentialRequest)
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
