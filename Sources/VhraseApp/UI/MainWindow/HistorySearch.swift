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

  /// Normalizes and tokenizes each saved transcript once, so renders and keystrokes reuse the work until the history changes.
  struct Index {
    fileprivate let documents: [SearchDocument]
    /// Caches the separate language-aware word count so archive statistics do not retokenize on every render.
    let wordCount: Int

    init(_ items: [TranscriptHistoryItem]) {
      documents = items.map(SearchDocument.init)
      wordCount = items.reduce(0) { $0 + $1.wordCount }
    }
  }

  /// Filters the complete archive first, then applies BM25-style local ranking without a network request.
  static func matches(
    _ index: Index,
    query: String,
    dateFilter: HistoryDateFilter,
    provider: String,
    customRange: ClosedRange<Date>? = nil,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> [TranscriptHistoryItem] {
    let includesDate = dateFilter.predicate(
      relativeTo: now, calendar: calendar, customRange: customRange)
    let documents = index.documents.filter { document in
      includesDate(document.item.createdAt)
        && (provider.isEmpty
          || document.item.provider.localizedCaseInsensitiveCompare(provider) == .orderedSame)
    }
    let normalizedQuery = normalize(query)
    guard !normalizedQuery.isEmpty else {
      return documents.map(\.item).sorted { $0.createdAt > $1.createdAt }
    }

    let queryTerms = uniqueTerms(in: normalizedQuery)
    let averageLength =
      documents.isEmpty
      ? 1
      : Double(documents.reduce(0) { $0 + $1.length }) / Double(documents.count)
    let minimumCoverage = max(1, Int(ceil(Double(queryTerms.count) * 0.6)))
    // Corpus frequency is constant across candidates; compute it once per query term.
    let inverseFrequencies = queryTerms.map { term in
      let documentFrequency = documents.reduce(into: 0) { count, candidate in
        if candidate.contains(term) {
          count += 1
        }
      }
      return log(
        1 + (Double(documents.count - documentFrequency) + 0.5)
          / (Double(documentFrequency) + 0.5))
    }

    return documents.compactMap { document -> RankedItem? in
      var matchedTerms = 0
      var score = 0.0
      for (term, inverseFrequency) in zip(queryTerms, inverseFrequencies) {
        let textFrequency = termFrequency(
          term, counts: document.textTermCounts, normalized: document.text)
        let metadataFrequency = termFrequency(
          term, counts: document.metadataTermCounts, normalized: document.metadata)
        let frequency = textFrequency + metadataFrequency * 2
        guard frequency > 0 else {
          continue
        }
        matchedTerms += 1
        let lengthAdjustment = 1 - 0.75 + 0.75 * Double(document.length) / averageLength
        score += inverseFrequency * (frequency * 2.2) / (frequency + 1.2 * lengthAdjustment)
      }
      guard matchedTerms >= minimumCoverage else {
        return nil
      }
      if document.text.contains(normalizedQuery) {
        score += 4
      }
      if document.metadata.contains(normalizedQuery) {
        score += 6
      }
      return RankedItem(item: document.item, score: score)
    }
    .sorted { left, right in
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

  fileprivate struct SearchDocument {
    let item: TranscriptHistoryItem
    let text: String
    let metadata: String
    let textTermCounts: [String: Int]
    let metadataTermCounts: [String: Int]
    let length: Int

    init(item: TranscriptHistoryItem) {
      self.item = item
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

    /// Terms hold only alphanumerics, so a substring match can never span the text and metadata boundary.
    func contains(_ term: String) -> Bool {
      textTermCounts[term] != nil || metadataTermCounts[term] != nil
        || text.contains(term) || metadata.contains(term)
    }
  }

  private struct RankedItem {
    let item: TranscriptHistoryItem
    let score: Double
  }

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
