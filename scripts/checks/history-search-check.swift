// Verifies bounded transcript-history discovery across lexical ranking and user-facing filters.

import Foundation

@main
struct HistorySearchCheck {
  static func main() {
    let calendar = Calendar(identifier: .gregorian)
    let now = Date(timeIntervalSince1970: 2_000_000)
    let recent = item(
      text: "Draft the quarterly launch plan for Hong Kong",
      provider: "Gemini",
      createdAt: now.addingTimeInterval(-60)
    )
    let older = item(
      text: "Quarterly planning notes and launch checklist",
      provider: "Grok",
      createdAt: now.addingTimeInterval(-8 * 86_400)
    )
    let metadataMatch = item(
      text: "Send this short message",
      provider: "ElevenLabs",
      targetAppName: "Notes",
      createdAt: now.addingTimeInterval(-120)
    )
    let unrelated = item(
      text: "Book a table for dinner",
      provider: "Gemini",
      createdAt: now.addingTimeInterval(-180)
    )
    let items = [older, unrelated, metadataMatch, recent]

    let ranked = HistorySearch.matches(
      items,
      query: "quarterly launch",
      dateFilter: .anyTime,
      provider: "",
      now: now,
      calendar: calendar
    )
    precondition(ranked.map(\.id) == [recent.id, older.id])

    let providerMatches = HistorySearch.matches(
      items,
      query: "",
      dateFilter: .anyTime,
      provider: "Gemini",
      now: now,
      calendar: calendar
    )
    precondition(providerMatches.map(\.id) == [recent.id, unrelated.id])

    let recentMatches = HistorySearch.matches(
      items,
      query: "",
      dateFilter: .lastSevenDays,
      provider: "",
      now: now,
      calendar: calendar
    )
    precondition(!recentMatches.contains { $0.id == older.id })

    let destinationMatches = HistorySearch.matches(
      items,
      query: "notes",
      dateFilter: .anyTime,
      provider: "",
      now: now,
      calendar: calendar
    )
    precondition(destinationMatches.first?.id == metadataMatch.id)
    precondition(destinationMatches.contains { $0.id == older.id })
    let day = calendar.startOfDay(for: recent.createdAt)
    let customMatches = HistorySearch.matches(
      items, query: "", dateFilter: .custom, provider: "", customRange: day...day,
      now: now, calendar: calendar)
    precondition(customMatches.map(\.id) == [recent.id, metadataMatch.id, unrelated.id])
    precondition(HistorySearch.matches(items, query: "", dateFilter: .custom, provider: "").isEmpty)
    let cleared = HistorySearch.matches(items, query: "  \n", dateFilter: .anyTime, provider: "")
    precondition(cleared.map(\.id) == [recent.id, metadataMatch.id, unrelated.id, older.id])
  }

  private static func item(
    text: String,
    provider: String,
    targetAppName: String? = nil,
    createdAt: Date
  ) -> TranscriptHistoryItem {
    TranscriptHistoryItem(
      id: UUID(),
      createdAt: createdAt,
      text: text,
      provider: provider,
      transcriptionMode: "Upload",
      cleanup: .raw,
      targetAppName: targetAppName,
      targetAppBundleIdentifier: nil
    )
  }
}
