// Owns lightweight lexical ranking and filters for the local transcript archive.

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

  /// Applies date presets and inclusive custom calendar days in the user's time zone.
  func includes(
    _ date: Date, relativeTo now: Date, calendar: Calendar,
    customRange: ClosedRange<Date>? = nil
  ) -> Bool {
    switch self {
    case .anyTime:
      return true
    case .today:
      return calendar.isDate(date, inSameDayAs: now)
    case .yesterday:
      guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return false }
      return calendar.isDate(date, inSameDayAs: yesterday)
    case .custom:
      return customRange.map { $0.contains(calendar.startOfDay(for: date)) } == true
    case .lastSevenDays, .lastThirtyDays:
      guard
        let start = calendar.date(
          byAdding: .day, value: self == .lastSevenDays ? -6 : -29,
          to: calendar.startOfDay(for: now))
      else {
        return true
      }
      return date >= start
    }
  }
}

struct HistorySearch {
  static let visibleLimit = 20

  /// Filters the complete archive first, then applies BM25-style local ranking without an index or network request.
  static func matches(
    _ items: [TranscriptHistoryItem],
    query: String,
    dateFilter: HistoryDateFilter,
    provider: String,
    customRange: ClosedRange<Date>? = nil,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> [TranscriptHistoryItem] {
    let filtered = items.filter { item in
      dateFilter.includes(item.createdAt, relativeTo: now, calendar: calendar, customRange: customRange)
        && (provider.isEmpty
          || item.provider.localizedCaseInsensitiveCompare(provider) == .orderedSame)
    }
    let normalizedQuery = normalize(query)
    guard !normalizedQuery.isEmpty else {
      return filtered.sorted { $0.createdAt > $1.createdAt }
    }

    let queryTerms = uniqueTerms(in: normalizedQuery)
    let documents = filtered.map(SearchDocument.init)
    let averageLength =
      documents.isEmpty
      ? 1
      : Double(documents.reduce(0) { $0 + $1.length }) / Double(documents.count)
    let minimumCoverage = max(1, Int(ceil(Double(queryTerms.count) * 0.6)))
    // Corpus frequency is constant across candidates; compute it once per query term.
    let inverseFrequencies = queryTerms.map { term in
      let documentFrequency = documents.reduce(into: 0) { count, candidate in
        if termFrequency(term, terms: candidate.allTerms, normalized: candidate.searchable) > 0 {
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
          term, terms: document.textTerms, normalized: document.text)
        let metadataFrequency = termFrequency(
          term, terms: document.metadataTerms, normalized: document.metadata)
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

  private struct SearchDocument {
    let item: TranscriptHistoryItem
    let text: String
    let metadata: String
    let textTerms: [String]
    let metadataTerms: [String]

    init(item: TranscriptHistoryItem) {
      self.item = item
      text = normalize(item.text)
      metadata = normalize(
        [item.provider, item.transcriptionMode, item.cleanup.title, item.targetAppName]
          .compactMap(\.self)
          .joined(separator: " ")
      )
      textTerms = terms(in: text)
      metadataTerms = terms(in: metadata)
    }

    var allTerms: [String] { textTerms + metadataTerms }
    var searchable: String { "\(text) \(metadata)" }
    var length: Int { max(allTerms.count, 1) }
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

  private static func termFrequency(
    _ term: String,
    terms: [String],
    normalized: String
  ) -> Double {
    let exactCount = terms.reduce(into: 0) { count, candidate in
      if candidate == term {
        count += 1
      }
    }
    if exactCount > 0 {
      return Double(exactCount)
    }
    return normalized.contains(term) ? 0.5 : 0
  }
}
