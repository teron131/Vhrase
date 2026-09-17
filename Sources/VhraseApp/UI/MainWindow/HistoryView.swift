// Presents saved dictation statistics and a searchable transcript archive.

import SwiftUI

struct HistoryView: View {
  @ObservedObject var appState: AppState
  @Binding var browsing: HistoryBrowsingState
  @State private var isClearHistoryConfirmationPresented = false
  private var presentation: DictationPresentation { appState.presentation }

  var body: some View {
    let page = HistorySearch.Page(matches: historyMatches, requestedIndex: browsing.pageIndex)
    return historyTab(page).mainWindowEvents(
      appState: appState, blocksEscape: isClearHistoryConfirmationPresented)
  }

  private var historyMatches: [TranscriptHistoryItem] {
    HistorySearch.matches(
      appState.history,
      query: browsing.query,
      dateFilter: browsing.dateFilter,
      provider: browsing.provider,
      customRange: Calendar.current.startOfDay(
        for: browsing.startDate)...Calendar.current.startOfDay(for: browsing.endDate)
    )
  }

  private func historyTab(_ page: HistorySearch.Page) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        HStack(alignment: .firstTextBaseline) {
          sectionHeader("Activity", description: "A local summary of your saved dictations.")
          Spacer()
          Toggle(
            "Save future transcripts",
            isOn: Binding(
              get: { appState.savesTranscriptHistory },
              set: { appState.updateTranscriptHistorySaving($0) }
            )
          )
          .toggleStyle(.switch)
          .help(
            "Keep future transcripts on this Mac. Turning this off does not delete anything already saved."
          )
        }

        historyStatsCard
        historyActivityCard

        HStack(alignment: .firstTextBaseline) {
          sectionHeader("Recent transcripts", description: historyCountTitle(page))
          Spacer()
          if page.count > 1 {
            Button {
              browsing.pageIndex = max(0, page.index - 1)
            } label: {
              Label("Newer", systemImage: "chevron.left")
            }
            .buttonStyle(AccentLinkButtonStyle())
            .disabled(page.index == 0)

            Text("\(page.index + 1) of \(page.count)")
              .font(VhraseFont.micro.monospacedDigit())
              .foregroundStyle(VhraseTheme.inkSecondary)

            Button {
              browsing.pageIndex = min(page.count - 1, page.index + 1)
            } label: {
              Label("Older", systemImage: "chevron.right")
                .labelStyle(.titleAndIcon)
            }
            .buttonStyle(AccentLinkButtonStyle())
            .disabled(page.index == page.count - 1)
          }
          Button(role: .destructive) {
            isClearHistoryConfirmationPresented = true
          } label: {
            Label("Clear", systemImage: "trash")
          }
          .buttonStyle(AccentLinkButtonStyle())
          .disabled(appState.history.isEmpty)
        }

        if !appState.history.isEmpty {
          historySearchControls
          if browsing.dateFilter == .custom {
            HStack(spacing: 16) {
              DatePicker(
                "From", selection: $browsing.startDate, in: ...browsing.endDate,
                displayedComponents: .date)
              DatePicker(
                "Through", selection: $browsing.endDate, in: browsing.startDate...,
                displayedComponents: .date)
              Spacer()
            }
            .datePickerStyle(.field)
            .onChange(of: browsing.startDate) { _, _ in browsing.pageIndex = 0 }
            .onChange(of: browsing.endDate) { _, _ in browsing.pageIndex = 0 }
          }
        }

        if appState.history.isEmpty {
          historyEmptyState
            .frame(maxWidth: .infinity, minHeight: 220)
        } else if page.matchCount == 0 {
          ContentUnavailableView(
            "No matching transcripts",
            systemImage: "magnifyingglass",
            description: Text("Try a different keyword or filter.")
          )
          .frame(maxWidth: .infinity, minHeight: 220)
        } else {
          VStack(spacing: 0) {
            HStack(spacing: 16) {
              Text("Transcript").frame(maxWidth: .infinity, alignment: .leading)
              Text("Date").frame(width: 100, alignment: .leading)
              Text("Source / App").frame(width: 112, alignment: .leading)
              Color.clear.frame(width: 48, height: 1)
            }
            .font(VhraseFont.micro)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
            ScrollView {
              LazyVStack(spacing: 0) {
                ForEach(page.items) { item in
                  HistoryTranscriptRow(
                    item: item,
                    metadata: presentation.historyMetadata(item),
                    onCopy: { appState.copyHistoryItem(item) },
                    onDelete: { appState.deleteHistoryItem(item) }
                  )
                  Divider().padding(.horizontal, 16)
                }
              }
            }
            .frame(height: 460)
          }
          .background(VhraseTheme.card)
          .clipShape(RoundedRectangle(cornerRadius: VhraseTheme.sectionCornerRadius))
          .overlay {
            RoundedRectangle(cornerRadius: VhraseTheme.sectionCornerRadius)
              .strokeBorder(VhraseTheme.hairline)
          }
          .id(historyListIdentity(pageIndex: page.index))
        }
      }
      .frame(maxWidth: 1040, alignment: .topLeading)
      .padding(32)
      .frame(maxWidth: .infinity, alignment: .top)
    }
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
    .onChange(of: browsing.query) { _, _ in
      browsing.pageIndex = 0
    }
    .onChange(of: browsing.dateFilter) { _, _ in
      browsing.pageIndex = 0
    }
    .onChange(of: browsing.provider) { _, _ in
      browsing.pageIndex = 0
    }
    .onChange(of: appState.history.count) { _, _ in
      browsing.pageIndex = min(browsing.pageIndex, page.count - 1)
    }
  }

  private var historySearchControls: some View {
    HStack(spacing: 10) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(VhraseTheme.inkSecondary)
        .accessibilityHidden(true)

      TextField("Search all saved transcripts", text: $browsing.query)
        .textFieldStyle(.plain)
        .accessibilityLabel("Search transcript history")

      if !browsing.query.isEmpty {
        Button {
          browsing.query = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
        }
        .buttonStyle(.plain)
        .foregroundStyle(VhraseTheme.inkSecondary)
        .help("Clear search")
        .accessibilityLabel("Clear history search")
      }

      Divider().frame(height: 20)

      Picker("Date", selection: $browsing.dateFilter) {
        ForEach(HistoryDateFilter.allCases) { filter in
          Text(filter.title).tag(filter)
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .fixedSize()
      .accessibilityLabel("History date filter")

      HistoryProviderPicker(selection: $browsing.provider, providers: historyProviders)
        .fixedSize()
        .accessibilityLabel("History provider filter")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 9)
    .insetField()
  }

  private var historyStatsCard: some View {
    HStack(spacing: 18) {
      HistoryMetric(
        value: "\(appState.transcriptsTodayCount)",
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

  private var historyActivityCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      sectionHeader("Last 7 days", description: "Saved dictations by day.")
      HistoryActivityChart(days: historyDays)
        .frame(height: 128)
    }
    .contentSection()
  }

  @ViewBuilder
  private var historyEmptyState: some View {
    ContentUnavailableView {
      Label("No saved transcripts", systemImage: "text.bubble")
        .foregroundStyle(VhraseTheme.accent)
    } description: {
      Text(
        appState.savesTranscriptHistory
          ? "Future completed dictations will appear here."
          : "History saving is off. Existing transcripts remain on this Mac."
      )
    } actions: {
      Button(appState.savesTranscriptHistory ? "Run a demo dictation" : "Enable history saving") {
        if appState.savesTranscriptHistory {
          appState.runDemoDictation()
        } else {
          appState.updateTranscriptHistorySaving(true)
        }
      }
      .buttonStyle(.borderedProminent)
      .tint(VhraseTheme.accent)
    }
  }

  private var historyWeekCount: Int {
    guard
      let weekStart = Calendar.current.date(
        byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date()))
    else {
      return 0
    }
    return appState.history.filter { $0.createdAt >= weekStart }.count
  }

  private var historyWordCount: Int {
    appState.history.reduce(into: 0) { count, item in
      count += item.wordCount
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
        let nextDate = calendar.date(byAdding: .day, value: 1, to: date)
      else {
        return nil
      }
      let count = appState.history.filter { $0.createdAt >= date && $0.createdAt < nextDate }.count
      return HistoryDay(date: date, count: count)
    }
  }

  private func historyCountTitle(_ page: HistorySearch.Page) -> String {
    if appState.history.isEmpty {
      return "Nothing saved"
    }
    guard page.matchCount > 0 else {
      return "No results"
    }
    let start = page.index * HistorySearch.visibleLimit + 1
    let end = start + page.items.count - 1
    let resultLabel = page.matchCount == 1 ? "result" : "results"
    if browsing.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      browsing.dateFilter == .anyTime,
      browsing.provider.isEmpty
    {
      return "\(start)–\(end) of \(appState.history.count)"
    }
    return "\(start)–\(end) of \(page.matchCount) \(resultLabel)"
  }

  private var historyProviders: [String] {
    Array(Set(appState.history.map(\.provider))).sorted {
      $0.localizedStandardCompare($1) == .orderedAscending
    }
  }

  private func historyListIdentity(pageIndex: Int) -> String {
    "\(pageIndex)|\(browsing.query)|\(browsing.dateFilter.rawValue)|\(browsing.provider)|\(browsing.startDate)|\(browsing.endDate)"
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

/// Expands complete selectable text below an aligned summary without inheriting table-cell truncation.
private struct HistoryTranscriptRow: View {
  let item: TranscriptHistoryItem
  let metadata: String
  let onCopy: () -> Void
  let onDelete: () -> Void
  @State private var isExpanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 16) {
        Button {
          isExpanded.toggle()
        } label: {
          HStack(spacing: 10) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.secondary)
              .frame(width: 10)
            Text(item.text.replacingOccurrences(of: "\n", with: " "))
              .lineLimit(1)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Collapse transcript" : "Read full transcript")
        VStack(alignment: .leading, spacing: 3) {
          Text(
            item.createdAt,
            format: Date.VerbatimFormatStyle(
              format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)",
              timeZone: .current, calendar: Calendar(identifier: .gregorian)))
          Text(
            item.createdAt,
            format: Date.VerbatimFormatStyle(
              format:
                "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)",
              timeZone: .current, calendar: Calendar(identifier: .gregorian))
          )
          .foregroundStyle(.tertiary)
        }
        .font(.caption)
        .frame(width: 100, alignment: .leading)
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 6) {
            if let icon = ProviderPicker.icon(forHistoryLabel: item.provider) {
              Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
            }
            Text(item.provider)
          }
          Text(item.targetAppName ?? "—").foregroundStyle(.tertiary)
        }
        .font(.caption)
        .lineLimit(1)
        .frame(width: 112, alignment: .leading)
        HStack(spacing: 12) {
          Button(action: onCopy) { Image(systemName: "doc.on.doc") }
            .help("Copy transcript")
            .accessibilityLabel("Copy transcript")
          Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
            .help("Delete transcript")
            .accessibilityLabel("Delete transcript")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .frame(width: 48)
      }
      .padding(16)
      if isExpanded {
        VStack(alignment: .leading, spacing: 12) {
          Text(metadata)
            .font(VhraseFont.micro)
            .foregroundStyle(.secondary)
          HStack(spacing: 24) {
            metric("Words", value: item.wordCount.formatted())
            metric("Recording", value: seconds(item.recordingSeconds))
            metric("Transcription", value: seconds(item.transcriptionSeconds))
              .help(
                "Upload request time, or time to finish the stream after stopping realtime recording."
              )
            metric("Processing", value: seconds(item.processingSeconds))
              .help(
                "Total time from stopping recording through transcription, cleanup, and delivery.")
          }
          if item.recordingSeconds == nil {
            Text("Timing was not recorded for this entry.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Text(item.text)
            .font(.body)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 20)
      }
    }
    .background(isExpanded ? VhraseTheme.field : Color.clear)
  }

  private func metric(_ label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label).font(.caption).foregroundStyle(.secondary)
      Text(value).font(.callout.monospacedDigit())
    }
  }

  private func seconds(_ value: Double?) -> String {
    value.map { "\($0.formatted(.number.precision(.fractionLength(2)))) s" } ?? "—"
  }
}

/// Retains archive navigation for the lifetime of the main window without retaining active view resources.
struct HistoryBrowsingState {
  var query = ""
  var dateFilter = HistoryDateFilter.anyTime
  var startDate = Calendar.current.startOfDay(for: Date())
  var endDate = Calendar.current.startOfDay(for: Date())
  var provider = ""
  var pageIndex = 0
}
