// Presents saved dictation statistics and a searchable transcript archive.

import SwiftUI

extension MainWindowView {
    var historyTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    sectionHeader("Activity", description: "A local summary of your saved dictations.")
                    Spacer()
                    if !appState.savesTranscriptHistory {
                        Button {
                            selectedTab = .output
                        } label: {
                            Label("History saving is off", systemImage: "pause.circle")
                        }
                        .buttonStyle(.link)
                    }
                }

                historyStatsCard
                historyActivityCard

                HStack(alignment: .firstTextBaseline) {
                    sectionHeader("Recent transcripts", description: historyCountTitle)
                    Spacer()
                    Button(role: .destructive) {
                        isClearHistoryConfirmationPresented = true
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(appState.history.isEmpty)
                }

                if appState.history.isEmpty {
                    historyEmptyState
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else if filteredHistory.isEmpty {
                    ContentUnavailableView(
                        "No matching transcripts",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different search.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredHistory) { item in
                            HistoryCardRow(
                                item: item,
                                metadata: presentation.historyMetadata(item),
                                onCopy: { appState.copyHistoryItem(item) },
                                onDelete: { appState.deleteHistoryItem(item) }
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: 1040, alignment: .topLeading)
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .top)
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

    var historyStatsCard: some View {
        HStack(spacing: 18) {
            HistoryMetric(
                value: "\(historyTodayCount)",
                label: "Today",
                detail: "saved dictations"
            )
            Divider().frame(height: 50)
            HistoryMetric(
                value: "\(historyWeekCount)",
                label: "Last 7 days",
                detail: "saved dictations"
            )
            Divider().frame(height: 50)
            HistoryMetric(
                value: historyWordCount.formatted(),
                label: "Words",
                detail: "across saved text"
            )
            Divider().frame(height: 50)
            HistoryMetric(
                value: historyTopDestination,
                label: "Top destination",
                detail: "among saved items"
            )
        }
        .contentSection()
    }

    var historyActivityCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Last 7 days", description: "Saved dictations by day.")
            HistoryActivityChart(days: historyDays)
                .frame(height: 128)
        }
        .contentSection()
    }

    @ViewBuilder
    var historyEmptyState: some View {
        ContentUnavailableView {
            Label("No saved transcripts", systemImage: "text.bubble")
                .foregroundStyle(VhraseTheme.accent)
        } description: {
            Text(
                appState.savesTranscriptHistory
                    ? "Future completed dictations will appear here."
                    : "History saving is off. You can enable it in Output."
            )
        } actions: {
            Button(appState.savesTranscriptHistory ? "Run a demo dictation" : "Open Output settings") {
                if appState.savesTranscriptHistory {
                    appState.runDemoDictation()
                } else {
                    selectedTab = .output
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(VhraseTheme.accent)
        }
    }

    private var historyTodayCount: Int {
        appState.history.filter { Calendar.current.isDateInToday($0.createdAt) }.count
    }

    private var historyWeekCount: Int {
        guard let weekStart = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date())) else {
            return 0
        }
        return appState.history.filter { $0.createdAt >= weekStart }.count
    }

    private var historyWordCount: Int {
        appState.history.reduce(into: 0) { count, item in
            count += item.text.split(whereSeparator: { $0.isWhitespace }).count
        }
    }

    private var historyTopDestination: String {
        let destinations = appState.history.compactMap(\.targetAppName)
        let counts = destinations.reduce(into: [String: Int]()) { result, destination in
            result[destination, default: 0] += 1
        }
        guard let highestCount = counts.values.max() else {
            return "—"
        }
        return destinations.first { counts[$0] == highestCount } ?? "—"
    }

    private var historyDays: [HistoryDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).compactMap { index in
            guard let date = calendar.date(byAdding: .day, value: index - 6, to: today),
                  let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else {
                return nil
            }
            let count = appState.history.filter { $0.createdAt >= date && $0.createdAt < nextDate }.count
            return HistoryDay(date: date, count: count)
        }
    }

    private var historyCountTitle: String {
        switch appState.history.count {
        case 0: "Nothing saved"
        case 1: "1 item on this Mac"
        default: "\(appState.history.count) items on this Mac"
        }
    }
}

private struct HistoryDay: Identifiable {
    let date: Date
    let count: Int

    var id: Date { date }
}

private struct HistoryMetric: View {
    let value: String
    let label: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(VhraseFont.statValue)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .contentTransition(.numericText())
            Text(label)
                .font(.callout.weight(.medium))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HistoryActivityChart: View {
    let days: [HistoryDay]

    var body: some View {
        GeometryReader { proxy in
            let plotHeight = max(proxy.size.height - 34, 1)
            let maximum = max(days.map(\.count).max() ?? 0, 1)

            HStack(alignment: .bottom, spacing: 12) {
                ForEach(days) { day in
                    VStack(spacing: 6) {
                        Spacer(minLength: 0)
                        Text(day.count.formatted())
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .opacity(day.count == 0 ? 0 : 1)

                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(day.count == 0 ? VhraseTheme.field : VhraseTheme.accent)
                            .frame(height: max(5, plotHeight * CGFloat(day.count) / CGFloat(maximum)))

                        Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide)))
                    .accessibilityValue("\(day.count) saved dictations")
                }
            }
        }
    }
}

private struct HistoryCardRow: View {
    private enum Action: Hashable {
        case copy
        case delete
    }

    let item: TranscriptHistoryItem
    let metadata: String
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @FocusState private var focusedAction: Action?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.text)
                .font(VhraseFont.transcript)
                .lineLimit(3)
                .textSelection(.enabled)

            HStack(spacing: 10) {
                Text(metadata)
                    .font(VhraseFont.micro)
                    .foregroundStyle(VhraseTheme.inkSecondary)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 8) {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                    }
                    .focused($focusedAction, equals: .copy)
                    .help("Copy transcript")
                    .accessibilityLabel("Copy transcript")

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .focused($focusedAction, equals: .delete)
                    .help("Delete transcript")
                    .accessibilityLabel("Delete transcript")
                }
                .buttonStyle(.borderless)
                .opacity(isHovered || focusedAction != nil ? 1 : 0)
            }
        }
        .padding(16)
        .background(VhraseTheme.card, in: RoundedRectangle(cornerRadius: VhraseTheme.sectionCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VhraseTheme.sectionCornerRadius, style: .continuous)
                .strokeBorder(isHovered ? VhraseTheme.accent.opacity(0.28) : VhraseTheme.hairline, lineWidth: 1)
        }
        .onHover { isHovered = $0 }
        .animation(
            VhraseMotion.respectingReduceMotion(VhraseMotion.snappy, reduceMotion: reduceMotion),
            value: isHovered
        )
        .contextMenu {
            Button("Copy", action: onCopy)
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}
