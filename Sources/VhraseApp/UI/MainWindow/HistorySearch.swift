// Owns lightweight lexical ranking, filters, and the reusable index for the local transcript archive.

import Foundation

enum HistoryDateFilter: String, CaseIterable, Identifiable {
  case anyTime
  case today
  case yesterday
  case lastSevenDays
  case lastThirtyDays
  case custom

  var id: String { rawValue }

  var title: String {
    switch self {
    case .anyTime: "Any time"
    case .today: "Today"
    case .yesterday: "Yesterday"
    case .lastSevenDays: "Last 7 days"
    case .lastThirtyDays: "Last 30 days"
    case .custom: "Custom range"
    }
  }

  /// Resolves preset calendar boundaries once per search while retaining inclusive custom calendar days.
  fileprivate func predicate(
    relativeTo now: Date, calendar: Calendar, customRange: ClosedRange<Date>?
  ) -> (Date) -> Bool {
    switch self {
    case .anyTime:
      return { _ in true }
    case .today, .yesterday:
      guard let day = self == .today ? now : calendar.date(byAdding: .day, value: -1, to: now)
      else { return { _ in false } }
      guard let interval = calendar.dateInterval(of: .day, for: day) else {
        return { calendar.isDate($0, inSameDayAs: day) }
      }
      return { $0 >= interval.start && $0 < interval.end }
    case .custom:
      guard let customRange else { return { _ in false } }
      return { customRange.contains(calendar.startOfDay(for: $0)) }
    case .lastSevenDays, .lastThirtyDays:
      guard
        let start = calendar.date(
          byAdding: .day, value: self == .lastSevenDays ? -6 : -29,
          to: calendar.startOfDay(for: now))
      else {
        return { _ in true }
      }
      return { $0 >= start }
    }
  }
}

struct HistorySearch {
  static let visibleLimit = 20

  /// Owns one archive snapshot and its derived results; replacing the index after a history edit invalidates every cached value together.
  @MainActor
  final class Index {
    private let documents: [SearchDocument]
    let wordCount: Int
    let providers: [String]
    /// The app that received the most saved transcripts, or `nil` when none recorded a destination.
    let topDestination: String?
    private var lastSearch: (query: Query, items: [TranscriptHistoryItem])?

    /// Takes each unchanged transcript's derived text, term counts, and word count from `previous`, so after a history edit only the changed transcript is tokenized.
    init(_ items: [TranscriptHistoryItem], reusing previous: Index? = nil) {
      let reusable = Dictionary(
        (previous?.documents ?? []).map { ($0.item.id, $0) },
        uniquingKeysWith: { first, _ in first })
      documents = items.map { item in
        if let document = reusable[item.id], document.item == item {
          return document
        }
        return SearchDocument(item: item)
      }
      wordCount = documents.reduce(0) { $0 + $1.wordCount }
      providers = Array(Set(items.map(\.provider))).sorted {
        $0.localizedStandardCompare($1) == .orderedAscending
      }
      let destinations = items.compactMap(\.targetAppName)
      let counts = destinations.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
      let highestCount = counts.values.max()
      topDestination = destinations.first { counts[$0] == highestCount }
    }

    /// Reuses the last ranking across unrelated app updates and page changes, expiring date filters at the next calendar day or time-zone change.
    func matches(
      query: String,
      dateFilter: HistoryDateFilter,
      provider: String,
      customRange: ClosedRange<Date>? = nil,
      now: Date = Date(),
      calendar: Calendar = .current
    ) -> [TranscriptHistoryItem] {
      let query = Query(
        text: normalize(query), dateFilter: dateFilter, provider: provider,
        customRange: customRange, day: CalendarDay(now: now, calendar: calendar))
      if let lastSearch, lastSearch.query == query { return lastSearch.items }
      let items = HistorySearch.rank(documents, query: query)
      lastSearch = (query, items)
      return items
    }
  }

  private struct CalendarDay: Equatable {
    let start: Date
    let calendar: Calendar

    init(now: Date, calendar: Calendar) {
      start = calendar.startOfDay(for: now)
      self.calendar = calendar
    }
  }

  private struct Query: Equatable {
    let text: String
    let dateFilter: HistoryDateFilter
    let provider: String
    let customRange: ClosedRange<Date>?
    let day: CalendarDay
  }

  /// Ranks in stages:
  /// 1. Keep transcripts inside the date and provider filters; an empty query returns them newest first.
  /// 2. Keep those matching at least 60% of the query's distinct terms in their text or metadata.
  /// 3. Score them BM25-style, metadata matches counting double and the whole query as a phrase earning a bonus.
  /// 4. Sort by score, newest first among ties.
  private static func rank(
    _ documents: [SearchDocument], query: Query
  ) -> [TranscriptHistoryItem] {
    let includesDate = query.dateFilter.predicate(
      relativeTo: query.day.start, calendar: query.day.calendar, customRange: query.customRange)
    let documents = documents.filter { document in
      includesDate(document.item.createdAt)
        && (query.provider.isEmpty
          || document.item.provider.localizedCaseInsensitiveCompare(query.provider) == .orderedSame)
    }
    let normalizedQuery = query.text
    guard !normalizedQuery.isEmpty else {
      return documents.map(\.item).sorted { $0.createdAt > $1.createdAt }
    }

    let queryTerms = uniqueTerms(in: normalizedQuery)
    guard !queryTerms.isEmpty else { return [] }
    let averageLength =
      documents.isEmpty
      ? 1
      : Double(documents.reduce(0) { $0 + $1.length }) / Double(documents.count)
    let minimumCoverage = max(1, Int(ceil(Double(queryTerms.count) * 0.6)))
    // Count corpus coverage and each candidate's term weights together, avoiding a second substring scan during scoring.
    var documentFrequencies = Array(repeating: 0, count: queryTerms.count)
    let candidates = documents.compactMap {
      document -> (document: SearchDocument, frequencies: [Double])? in
      var matchedTerms = 0
      let frequencies = queryTerms.enumerated().map { offset, term in
        let textFrequency = termFrequency(
          term, counts: document.textTermCounts, normalized: document.text)
        let metadataFrequency = termFrequency(
          term, counts: document.metadataTermCounts, normalized: document.metadata)
        let frequency = textFrequency + metadataFrequency * 2
        if frequency > 0 {
          matchedTerms += 1
          documentFrequencies[offset] += 1
        }
        return frequency
      }
      return matchedTerms >= minimumCoverage ? (document, frequencies) : nil
    }
    let inverseFrequencies = documentFrequencies.map { documentFrequency in
      log(
        1 + (Double(documents.count - documentFrequency) + 0.5)
          / (Double(documentFrequency) + 0.5))
    }

    let ranked = candidates.map { candidate -> RankedItem in
      let document = candidate.document
      var score = 0.0
      let lengthAdjustment = 1 - 0.75 + 0.75 * Double(document.length) / averageLength
      for (frequency, inverseFrequency) in zip(candidate.frequencies, inverseFrequencies)
      where frequency > 0 {
        score += inverseFrequency * (frequency * 2.2) / (frequency + 1.2 * lengthAdjustment)
      }
      if document.text.contains(normalizedQuery) {
        score += 4
      }
      if document.metadata.contains(normalizedQuery) {
        score += 6
      }
      return RankedItem(item: document.item, score: score)
    }
    return ranked.sorted { left, right in
      left.score > right.score
        || (left.score == right.score && left.item.createdAt > right.item.createdAt)
    }
    .map(\.item)
  }

  /// Keeps pagination on one immutable search result so rendering labels and rows never repeats lexical ranking.
  struct Page {
    let items: [TranscriptHistoryItem]
    let matchCount: Int
    let index: Int
    let count: Int

    init(matches: [TranscriptHistoryItem], requestedIndex: Int) {
      matchCount = matches.count
      count = max(1, (matchCount + HistorySearch.visibleLimit - 1) / HistorySearch.visibleLimit)
      index = min(max(0, requestedIndex), count - 1)
      items = Array(
        matches.dropFirst(index * HistorySearch.visibleLimit).prefix(HistorySearch.visibleLimit))
    }
  }

  private struct SearchDocument {
    let item: TranscriptHistoryItem
    let text: String
    let metadata: String
    let textTermCounts: [String: Int]
    let metadataTermCounts: [String: Int]
    let length: Int
    let wordCount: Int

    init(item: TranscriptHistoryItem) {
      self.item = item
      wordCount = item.wordCount
      text = normalize(item.text)
      metadata = normalize(
        [item.provider, item.transcriptionMode, item.cleanup.title, item.targetAppName]
          .compactMap(\.self)
          .joined(separator: " ")
      )
      let textTerms = terms(in: text)
      let metadataTerms = terms(in: metadata)
      textTermCounts = textTerms.reduce(into: [:]) { $0[$1, default: 0] += 1 }
      metadataTermCounts = metadataTerms.reduce(into: [:]) { $0[$1, default: 0] += 1 }
      length = max(textTerms.count + metadataTerms.count, 1)
    }
  }

  private struct RankedItem {
    let item: TranscriptHistoryItem
    let score: Double
  }

  /// `"  Café\tＮＯＴＥＳ "` → `"cafe notes"`: case, accents, and full-width forms fold away, and whitespace collapses.
  private static func normalize(_ value: String) -> String {
    value
      .folding(
        options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current
      )
      .lowercased()
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }

  private static func terms(in value: String) -> [String] {
    value.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
  }

  private static func uniqueTerms(in value: String) -> [String] {
    var seen = Set<String>()
    return terms(in: value).filter { seen.insert($0).inserted }
  }

  /// Weighs exact term matches fully and substring matches, such as word prefixes, at half weight.
  private static func termFrequency(
    _ term: String,
    counts: [String: Int],
    normalized: String
  ) -> Double {
    if let exactCount = counts[term] {
      return Double(exactCount)
    }
    return normalized.contains(term) ? 0.5 : 0
  }
}
