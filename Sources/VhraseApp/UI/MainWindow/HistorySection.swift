// Presents searchable transcript history and its copy, delete, and clear actions.

import SwiftUI

extension MainWindowView {
    var historyTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(appState.history.isEmpty ? "No saved transcripts" : "\(appState.history.count) saved transcripts")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) {
                    isClearHistoryConfirmationPresented = true
                } label: {
                    Label("Clear history", systemImage: "trash")
                }
                .disabled(appState.history.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            if appState.history.isEmpty {
                ContentUnavailableView(
                    "No transcripts yet",
                    systemImage: "text.bubble",
                    description: Text("Recorded and demo transcripts will appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredHistory.isEmpty {
                ContentUnavailableView(
                    "No matching transcripts",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different search.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredHistory) { item in
                    historyRow(item)
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $historyQuery, prompt: "Search transcripts")
        .confirmationDialog(
            "Clear transcript history?",
            isPresented: $isClearHistoryConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                appState.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes every saved transcript.")
        }
    }

    func historyRow(_ item: TranscriptHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(item.text)
                .font(.body)
                .lineLimit(4)
                .textSelection(.enabled)
            HStack(spacing: 10) {
                Text(historyMetadata(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button {
                    appState.copyHistoryItem(item)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy transcript")
                .accessibilityLabel("Copy transcript")

                Button {
                    appState.deleteHistoryItem(item)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete transcript")
                .accessibilityLabel("Delete transcript")
            }
        }
        .padding(.vertical, 7)
        .contextMenu {
            Button("Copy") {
                appState.copyHistoryItem(item)
            }
            Button("Delete", role: .destructive) {
                appState.deleteHistoryItem(item)
            }
        }
    }
}
