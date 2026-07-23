// Hosts Vhrase's sidebar control center and its selection-driven recording surfaces.

import SwiftUI

enum MainWindowTab: String, CaseIterable, Hashable, Identifiable {
    case dictate
    case capture
    case output
    case history
    case system

    var id: String { rawValue }

    init(storedRawValue: String) {
        self = MainWindowTab(rawValue: storedRawValue) ?? .dictate
    }

    var title: String {
        switch self {
        case .dictate: "Dictate"
        case .history: "History"
        case .capture: "Capture"
        case .output: "Output"
        case .system: "System"
        }
    }

    var detail: String {
        switch self {
        case .dictate: "Record and review"
        case .history: "Saved transcripts"
        case .capture: "Speech and shortcut"
        case .output: "Delivery and cleanup"
        case .system: "Access and readiness"
        }
    }

    var systemImage: String {
        switch self {
        case .dictate: "waveform"
        case .history: "clock.arrow.circlepath"
        case .capture: "mic.and.signal.meter"
        case .output: "text.badge.checkmark"
        case .system: "wrench.and.screwdriver"
        }
    }
}

struct MainWindowView: View {
    @ObservedObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("mainWindow.selectedTab") private var selectedTabRawValue = MainWindowTab.dictate.rawValue
    @State var isCapturingHotkey = false
    @State var isClearHistoryConfirmationPresented = false
    @State var isOpenCCInstallConfirmationPresented = false
    @State var historyQuery = ""
    @State var hoveredTab: MainWindowTab?
    @State var selectedCapturePipelineStage = PipelineStage.transcribe
    @State var selectedOutputPipelineStage = PipelineStage.enhance
    @State var credentialFocusMonitor = CredentialFocusMonitor()
    @FocusState var focusedSecretField: String?
    @Namespace var navigationSelection

    var selectedTab: MainWindowTab {
        get { MainWindowTab(storedRawValue: selectedTabRawValue) }
        nonmutating set { selectedTabRawValue = newValue.rawValue }
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(VhraseTheme.canvas)
        }
        .frame(minWidth: 1020, minHeight: 680)
        .tint(VhraseTheme.accent)
        .animation(
            VhraseMotion.respectingReduceMotion(VhraseMotion.stateSpring, reduceMotion: reduceMotion),
            value: selectedTab
        )
        .confirmationDialog(
            "Install OpenCC?",
            isPresented: $isOpenCCInstallConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Install with Homebrew") {
                appState.installOpenCC()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Vhrase will run “brew install opencc”. Homebrew may download OpenCC and its required packages.")
        }
        .onAppear {
            if selectedTabRawValue != selectedTab.rawValue {
                selectedTabRawValue = selectedTab.rawValue
            }
            appState.refreshPermissions()
        }
        .onChange(of: selectedTab) { oldTab, newTab in
            if newTab != .capture {
                cancelShortcutCaptureIfNeeded()
            }
            if oldTab == .system {
                finishAPIKeyEditing()
            }
        }
        .onChange(of: focusedSecretField) { _, field in
            if field != nil {
                credentialFocusMonitor.start(onOutsideClick: finishAPIKeyEditing)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                appState.refreshPermissions()
            }
        }
        .onDisappear {
            cancelShortcutCaptureIfNeeded()
            finishAPIKeyEditing()
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
            dictationTab
        case .history:
            historyTab
        case .capture:
            captureTab
        case .output:
            outputTab
        case .system:
            systemTab
        }
    }
}
