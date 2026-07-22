// Hosts Vhrase's native sidebar-detail control center and its window-level actions.

import SwiftUI

struct MainWindowView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openSettings) var openSettings
    @AppStorage("mainWindow.selectedTab") var selectedTab = MainWindowTab.dictation
    @State var isCapturingHotkey = false
    @State var isClearHistoryConfirmationPresented = false
    @State var historyQuery = ""
    @State var apiKeySaveTask: Task<Void, Never>?
    @State var pendingAPIKeySaves: Set<SecretKey> = []
    @FocusState var focusedSecretField: String?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 250)
        } detail: {
            content
                .navigationTitle(selectedTab.title)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 860, minHeight: 640)
        .accentColor(AppTheme.accent)
        .toolbar {
            if selectedTab != .dictation {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        handleRecordButton()
                    } label: {
                        Label(recordButtonTitle, systemImage: recordButtonSystemImage)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(recordButtonTint)
                    .disabled(presentation.recordAction == .disabled)
                    .help(recordButtonSubtitle)
                    .accessibilityHint(recordButtonSubtitle)
                }
            }
        }
        .onAppear {
            appState.refreshPermissions()
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab != .customize {
                cancelShortcutCaptureIfNeeded()
            }
        }
        .onDisappear {
            cancelShortcutCaptureIfNeeded()
            flushPendingAPIKeySave()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .dictation:
            dictationTab
        case .customize:
            customizeTab
        case .setup:
            setupTab
        case .history:
            historyTab
        }
    }
}
