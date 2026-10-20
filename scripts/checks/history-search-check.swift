// Verifies bounded transcript-history discovery across lexical ranking and user-facing filters.

import Foundation

@main
@MainActor
struct HistorySearchCheck {
  static func main() {
    let calendar = Calendar(identifier: .gregorian)
    let now = Date(timeIntervalSince1970: 2_000_000)
    let recent = item(
      text: "Draft the quarterly launch plan for Hong Kong",
      provider: "Gemini",
      targetAppName: "Mail",
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
    let index = HistorySearch.Index([older, unrelated, metadataMatch, recent])

    let ranked = index.matches(
      query: "quarterly launch",
      dateFilter: .anyTime,
      provider: "",
      now: now,
      calendar: calendar
    )
    precondition(ranked.map(\.id) == [recent.id, older.id])

    let providerMatches = index.matches(
      query: "",
      dateFilter: .anyTime,
      provider: "Gemini",
      now: now,
      calendar: calendar
    )
    precondition(providerMatches.map(\.id) == [recent.id, unrelated.id])

    let recentMatches = index.matches(
      query: "",
      dateFilter: .lastSevenDays,
      provider: "",
      now: now,
      calendar: calendar
    )
    precondition(!recentMatches.contains { $0.id == older.id })

    let destinationMatches = index.matches(
      query: "notes",
      dateFilter: .anyTime,
      provider: "",
      now: now,
      calendar: calendar
    )
    precondition(destinationMatches.first?.id == metadataMatch.id)
    precondition(destinationMatches.contains { $0.id == older.id })
    let day = calendar.startOfDay(for: recent.createdAt)
    let customMatches = index.matches(
      query: "", dateFilter: .custom, provider: "", customRange: day...day,
      now: now, calendar: calendar)
    precondition(customMatches.map(\.id) == [recent.id, metadataMatch.id, unrelated.id])
    precondition(index.matches(query: "", dateFilter: .custom, provider: "").isEmpty)
    let cleared = index.matches(query: "  \n", dateFilter: .anyTime, provider: "")
    precondition(cleared.map(\.id) == [recent.id, metadataMatch.id, unrelated.id, older.id])

    // Repeated renders reuse the ranking, but edits and calendar boundaries must refresh derived results.
    precondition(index.matches(query: "  \n", dateFilter: .anyTime, provider: "") == cleared)
    precondition(index.providers == ["ElevenLabs", "Gemini", "Grok"])
    precondition(index.topDestination == "Notes")
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
    let todayMatches = index.matches(
      query: "", dateFilter: .today, provider: "", now: now, calendar: calendar)
    precondition(todayMatches.count == 3)
    precondition(
      index.matches(query: "", dateFilter: .today, provider: "", now: tomorrow, calendar: calendar)
        .isEmpty)
    let afterEdit = HistorySearch.Index([older])
    precondition(afterEdit.matches(query: "", dateFilter: .anyTime, provider: "") == [older])
    precondition(afterEdit.providers == ["Grok"] && afterEdit.topDestination == nil)
    precondition(afterEdit.wordCount == older.wordCount)
    let boundary = HistorySearch.Index([
      item(
        text: "Late dictation", provider: "Gemini", createdAt: Date(timeIntervalSince1970: 85_000))
    ])
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(secondsFromGMT: 0)!
    var west = utc
    west.timeZone = TimeZone(secondsFromGMT: -7_200)!
    let afterMidnight = Date(timeIntervalSince1970: 90_000)
    precondition(
      boundary.matches(
        query: "", dateFilter: .today, provider: "", now: afterMidnight, calendar: utc
      ).isEmpty)
    precondition(
      boundary.matches(
        query: "", dateFilter: .today, provider: "", now: afterMidnight, calendar: west
      ).count == 1)

    let archive = (0..<41).map { index in
      item(
        text: "Entry \(index)", provider: "Gemini",
        createdAt: now.addingTimeInterval(Double(-index)))
    }
    let firstPage = HistorySearch.Page(matches: archive, requestedIndex: 0)
    precondition(firstPage.matchCount == 41 && firstPage.count == 3 && firstPage.index == 0)
    precondition(firstPage.items == Array(archive.prefix(20)))
    let secondPage = HistorySearch.Page(matches: archive, requestedIndex: 1)
    precondition(secondPage.items == Array(archive[20..<40]))
    let lastPage = HistorySearch.Page(matches: archive, requestedIndex: 2)
    precondition(lastPage.items == [archive[40]])
    let afterDeletion = HistorySearch.Page(matches: Array(archive.prefix(20)), requestedIndex: 2)
    precondition(afterDeletion.count == 1 && afterDeletion.index == 0)
    precondition(afterDeletion.items == Array(archive.prefix(20)))
    let emptyPage = HistorySearch.Page(matches: [], requestedIndex: 9)
    precondition(emptyPage.count == 1 && emptyPage.index == 0 && emptyPage.items.isEmpty)
    precondition(HistorySearch.Page(matches: archive, requestedIndex: -1).index == 0)
    print("history search and pagination ok")
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
