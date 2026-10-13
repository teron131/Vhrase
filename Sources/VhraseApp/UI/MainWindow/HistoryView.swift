// Presents saved dictation statistics and a searchable transcript archive.

import SwiftUI

struct HistoryView: View {
  @ObservedObject var appState: AppState
  @Binding var browsing: HistoryBrowsingState
  @State private var isClearHistoryConfirmationPresented = false

  var body: some View {
    let page = HistorySearch.Page(matches: historyMatches, requestedIndex: browsing.pageIndex)
    return historyTab(page).mainWindowEvents(
      appState: appState, blocksEscape: isClearHistoryConfirmationPresented)
  }

  private var historyMatches: [TranscriptHistoryItem] {
    appState.historyIndex.matches(
      query: browsing.query,
      dateFilter: browsing.dateFilter,
      provider: browsing.provider,
      customRange: Calendar.current.startOfDay(
        for: browsing.startDate)...Calendar.current.startOfDay(for: browsing.endDate)
    )
  }

  private func historyTab(_ page: HistorySearch.Page) -> some View {
    mainWindowPage(spacing: 22) {
      pageHeader(
        "History",
        description: "Saved transcripts stay on this Mac. Search, copy, or remove them here."
      ) {
        HStack(spacing: 10) {
          Text("Save future transcripts")
            .font(VhraseFont.pill)
          VhraseSwitch(
            title: "Save future transcripts",
            isOn: Binding(
              get: { appState.savesTranscriptHistory },
              set: { appState.updateTranscriptHistorySaving($0) }
            )
          )
        }
        .help(
          "Keep future transcripts on this Mac. Turning this off does not delete anything already saved."
        )
      }

      historyStatsCard

      VStack(alignment: .leading, spacing: 12) {
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
            ForEach(page.items) { item in
              HistoryTranscriptRow(
                item: item,
                metadata: DictationPresentation.historyMetadata(item),
                onCopy: { appState.copyHistoryItem(item) },
                onDelete: { appState.deleteHistoryItem(item) }
              )
            }
          }
          .mask {
            RoundedRectangle(cornerRadius: VhraseTheme.groupCornerRadius, style: .continuous)
              .padding(.top, 1)
          }
          .surface()
          .id(historyListIdentity(pageIndex: page.index))
        }

        if !appState.history.isEmpty {
          historyFooter(page)
        }
      }
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

  /// Keeps the irreversible clear action at the opposite edge from page navigation.
  private func historyFooter(_ page: HistorySearch.Page) -> some View {
    HStack(spacing: 12) {
      Button(role: .destructive) {
        isClearHistoryConfirmationPresented = true
      } label: {
        Label("Clear history…", systemImage: "trash")
      }
      .buttonStyle(AccentLinkButtonStyle())

      Spacer()

      Text(historyCountTitle(page))
        .font(VhraseFont.micro.monospacedDigit())
        .foregroundStyle(VhraseTheme.inkSecondary)

      if page.count > 1 {
        HStack(spacing: 4) {
          Button {
            browsing.pageIndex = max(0, page.index - 1)
          } label: {
            Label("Newer", systemImage: "chevron.left")
              .labelStyle(.iconOnly)
          }
          .help("Newer transcripts")
          .disabled(page.index == 0)

          Text("\(page.index + 1) of \(page.count)")
            .font(VhraseFont.micro.monospacedDigit())
            .foregroundStyle(VhraseTheme.inkSecondary)
            .frame(minWidth: 44)

          Button {
            browsing.pageIndex = min(page.count - 1, page.index + 1)
          } label: {
            Label("Older", systemImage: "chevron.right")
              .labelStyle(.iconOnly)
          }
          .help("Older transcripts")
          .disabled(page.index == page.count - 1)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
    }
    .font(.callout)
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

      Divider().frame(height: 18)

      Picker("Date", selection: $browsing.dateFilter) {
        ForEach(HistoryDateFilter.allCases) { filter in
          Text(filter.title).tag(filter)
        }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .fixedSize()
      .accessibilityLabel("History date filter")

      HistoryProviderPicker(
        selection: $browsing.provider, providers: appState.historyIndex.providers
      )
      .fixedSize()
      .accessibilityLabel("History provider filter")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
    .surface(cornerRadius: VhraseTheme.fieldCornerRadius + 2)
  }

  private var historyStatsCard: some View {
    let index = appState.historyIndex
    let counts = index.counts()
    return HStack(spacing: 10) {
      StatTile(value: "\(counts.today)", title: "Today", detail: "saved dictations")
      StatTile(value: "\(counts.week)", title: "Last 7 days", detail: "saved dictations")
      StatTile(
        value: index.wordCount.formatted(), title: "Words",
        detail: "across saved text")
      StatTile(value: index.topDestination, title: "Top destination", detail: "among saved items")
    }
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

  private func historyListIdentity(pageIndex: Int) -> String {
    "\(pageIndex)|\(browsing.query)|\(browsing.dateFilter.rawValue)|\(browsing.provider)|\(browsing.startDate)|\(browsing.endDate)"
  }
}

/// Shows each saved transcript as the user's words first, with when, how, and where beneath, expanding in place to the full text.
private struct HistoryTranscriptRow: View {
  let item: TranscriptHistoryItem
  let metadata: String
  let onCopy: () -> Void
  let onDelete: () -> Void
  @State private var isExpanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 12) {
        Button {
          isExpanded.toggle()
        } label: {
          HStack(alignment: .top, spacing: 10) {
            Image(systemName: "chevron.right")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.secondary)
              .rotationEffect(.degrees(isExpanded ? 90 : 0))
              .frame(width: 10, height: 18)
            VStack(alignment: .leading, spacing: 5) {
              if !isExpanded {
                Text(item.text.replacingOccurrences(of: "\n", with: " "))
                  .font(VhraseFont.transcriptBody)
                  .lineLimit(2)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              summaryLine
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Collapse transcript" : "Read full transcript")

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
        .padding(.top, 2)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)

      if isExpanded {
        VStack(alignment: .leading, spacing: 14) {
          Text(item.text)
            .font(VhraseFont.transcriptBody)
            .lineSpacing(3)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .frame(maxWidth: 680, alignment: .leading)
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
        }
        .padding(.leading, 34)
        .padding(.trailing, 14)
        .padding(.bottom, 16)
      }
    }
    .background(isExpanded ? VhraseTheme.field : Color.clear)
    .overlay(alignment: .top) {
      Rectangle()
        .fill(VhraseTheme.hairline)
        .frame(height: 1)
        .padding(.leading, 14)
    }
  }

  private var summaryLine: some View {
    HStack(spacing: 6) {
      Text(
        item.createdAt,
        format: Date.VerbatimFormatStyle(
          format:
            "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
          timeZone: .current, calendar: Calendar(identifier: .gregorian))
      )
      .monospacedDigit()
      Text("·")
      if let icon = ProviderPicker.icon(forHistoryLabel: item.provider) {
        Image(nsImage: icon)
          .resizable()
          .scaledToFit()
          .frame(width: 12, height: 12)
          .accessibilityHidden(true)
      }
      Text(item.provider)
      if let target = item.targetAppName {
        Image(systemName: "arrow.right")
          .font(.caption2)
          .accessibilityLabel("to")
        Text(target)
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .lineLimit(1)
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
