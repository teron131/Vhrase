// Presents Vhrase's compact, auto-saving macOS settings for defaults, keys, and permissions.

import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var apiKeySaveTask: Task<Void, Never>?
    @State private var pendingAPIKeySaves: Set<SecretKey> = []

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            keySettings
                .tabItem {
                    Label("API keys", systemImage: "key")
                }

            permissionSettings
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield")
                }
        }
        .frame(width: 540, height: 440)
        .padding(10)
        .onAppear {
            appState.refreshPermissions()
        }
        .onDisappear {
            flushPendingAPIKeySave()
        }
    }

    private var generalSettings: some View {
        Form {
            Section("Transcription") {
                Picker("Provider", selection: persistedBinding(\.provider)) {
                    ForEach(STTProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Mode", selection: persistedBinding(\.transcriptionMode)) {
                    ForEach(TranscriptionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Shortcut", selection: persistedBinding(\.hotkeyPreset)) {
                    ForEach(HotkeyPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }

                Picker("Shortcut behavior", selection: persistedBinding(\.shortcutBehavior)) {
                    ForEach(ShortcutBehavior.allCases) { behavior in
                        Text(behavior.title).tag(behavior)
                    }
                }
                .pickerStyle(.segmented)

                Text(appState.settings.shortcutBehavior.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(workflowControlsAreDisabled)

            Section("Output") {
                Toggle("Paste after transcription", isOn: persistedBinding(\.pasteAfterTranscription))
                Toggle("Clean up with an LLM", isOn: persistedBinding(\.adjustWithLLM))
                Toggle("Use local cleanup if the LLM fails", isOn: persistedBinding(\.useLocalAdjustmentFallback))
                    .disabled(!appState.settings.adjustWithLLM)
                Toggle("Use screenshot context", isOn: persistedBinding(\.includeScreenshot))
                    .disabled(!appState.settings.adjustWithLLM)
            }
            .disabled(workflowControlsAreDisabled)

            Section {
                Button {
                    openMainWindow()
                } label: {
                    Label("Open full configuration", systemImage: "macwindow")
                }
            } footer: {
                Text("Provider tuning, vocabulary, custom shortcuts, setup diagnostics, and transcript history live in the main Vhrase window.")
            }
        }
        .formStyle(.grouped)
    }

    private var keySettings: some View {
        Form {
            Section("Speech to text") {
                keyField("xAI API key", key: .xaiAPIKey, text: apiKeyBinding(.xaiAPIKey, \.xaiAPIKey))
                keyField("ElevenLabs API key", key: .elevenLabsAPIKey, text: apiKeyBinding(.elevenLabsAPIKey, \.elevenLabsAPIKey))
            }

            Section("Cleanup") {
                keyField("LLM API key", key: .llmAPIKey, text: apiKeyBinding(.llmAPIKey, \.llmAPIKey))
            }

            Section {
                Label("Keys are stored in your login Keychain after you finish editing.", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if hasEnvironmentCredential {
                    Text("Launch-environment credentials are active for this session and are not written into these Keychain fields.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !appState.customizationNotice.isEmpty {
                    Text(appState.customizationNotice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var permissionSettings: some View {
        Form {
            Section {
                ForEach(appState.permissions) { snapshot in
                    HStack(spacing: 10) {
                        Image(systemName: snapshot.permission.systemImage)
                            .frame(width: 20)
                            .foregroundStyle(snapshot.state.isReady ? Color.green : Color.orange)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(snapshot.permission.title)
                            Text(snapshot.displayTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(permissionActionTitle(snapshot)) {
                            appState.handlePermissionAction(snapshot)
                        }
                        .accessibilityLabel("\(permissionActionTitle(snapshot)) \(snapshot.permission.title) permission")
                    }
                }
            } header: {
                Text("macOS access")
            } footer: {
                Text("Microphone is required. Input Monitoring enables Fn/Globe outside Vhrase; Screen Recording and Accessibility support screenshot context and automatic paste.")
            }

            Section {
                Button {
                    appState.refreshPermissions()
                } label: {
                    Label("Refresh permissions", systemImage: "arrow.clockwise")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func keyField(
        _ title: String,
        key: SecretKey,
        text: Binding<String>
    ) -> some View {
        LabeledContent(title) {
            SecureField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
                .disabled(appState.usesEnvironmentOverride(for: key))
                .onSubmit {
                    flushPendingAPIKeySave()
                }
        }
    }

    private func permissionActionTitle(_ snapshot: PermissionSnapshot) -> String {
        if snapshot.state.isReady || snapshot.requestedBefore {
            return "Open"
        }
        switch snapshot.permission {
        case .microphone, .inputMonitoring:
            return "Request"
        case .screenRecording, .accessibility:
            return "Open"
        }
    }

    private func persistedBinding<Value>(
        _ keyPath: WritableKeyPath<DictationSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: {
                appState.settings[keyPath: keyPath]
            },
            set: { value in
                appState.updateSettings { settings in
                    settings[keyPath: keyPath] = value
                }
            }
        )
    }

    private func apiKeyBinding(
        _ key: SecretKey,
        _ keyPath: ReferenceWritableKeyPath<AppState, String>
    ) -> Binding<String> {
        Binding(
            get: {
                appState[keyPath: keyPath]
            },
            set: { value in
                appState[keyPath: keyPath] = value
                scheduleAPIKeySave(key)
            }
        )
    }

    private func scheduleAPIKeySave(_ key: SecretKey) {
        pendingAPIKeySaves.insert(key)
        apiKeySaveTask?.cancel()
        apiKeySaveTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            apiKeySaveTask = nil
            let keys = pendingAPIKeySaves
            pendingAPIKeySaves.removeAll()
            appState.saveAPIKeys(keys)
        }
    }

    private func flushPendingAPIKeySave() {
        guard apiKeySaveTask != nil else {
            return
        }
        apiKeySaveTask?.cancel()
        apiKeySaveTask = nil
        let keys = pendingAPIKeySaves
        pendingAPIKeySaves.removeAll()
        appState.saveAPIKeys(keys)
    }

    private var workflowControlsAreDisabled: Bool {
        switch appState.status {
        case .preparing, .recording, .transcribing, .adjusting:
            true
        case .idle, .completed, .failed:
            false
        }
    }

    private var hasEnvironmentCredential: Bool {
        SecretKey.allCases.contains { appState.usesEnvironmentOverride(for: $0) }
    }

    private func openMainWindow() {
        openWindow(id: "main")
        DispatchQueue.main.async {
            NSApplication.shared.activate()
        }
    }
}
