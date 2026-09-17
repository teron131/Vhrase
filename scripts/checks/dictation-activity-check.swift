// Verifies weighted activity metrics and calendar buckets shared by the summary and chart.

import Foundation

@main
struct DictationActivityCheck {
  static func main() {
    let slow = DictationActivityDay(
      date: Date(timeIntervalSince1970: 0),
      dictations: 1,
      words: 10,
      recordingSeconds: 65,
      processingSeconds: 5,
      estimatedCostUSD: 0
    )
    precondition(slow.savedSeconds == 0)
    precondition(abs(slow.dictatedWordsPerMinute - (120.0 / 13.0)) < 0.001)

    let fast = DictationActivityDay(
      date: Date(timeIntervalSince1970: 0),
      dictations: 1,
      words: 110,
      recordingSeconds: 60,
      processingSeconds: 5,
      estimatedCostUSD: 0
    )
    precondition(abs(fast.savedSeconds - 55) < 0.001)
    precondition(abs(fast.dictatedWordsPerMinute - 110) < 0.001)

    var aggregate = fast
    aggregate.add(slow)
    precondition(aggregate.savedSeconds == 0)
    precondition(abs(aggregate.dictatedWordsPerMinute - 57.6) < 0.001)

    let noDuration = DictationActivityDay(
      date: Date(timeIntervalSince1970: 0),
      dictations: 1,
      words: 20,
      recordingSeconds: 0,
      processingSeconds: 30,
      estimatedCostUSD: 0
    )
    precondition(noDuration.dictatedWordsPerMinute == 0)
    precondition(noDuration.savedSeconds == 0)

    verifyCalendarBuckets()
    print(
      "dictation activity metrics and calendar buckets ok (\(Calendar.current.timeZone.identifier))"
    )
  }

  /// Covers unsorted days, duplicate periods, future entries, leap day, and a week crossing a daylight-saving boundary.
  private static func verifyCalendarBuckets() {
    let calendar = Calendar.current
    func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
      calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
    func entry(_ date: Date, words: Int = 55, recordingSeconds: Double = 20) -> DictationActivityDay
    {
      DictationActivityDay(
        date: date, dictations: 1, words: words, recordingSeconds: recordingSeconds)
    }
    let now = date(2024, 3, 11, hour: 12)
    let days = [
      entry(date(2024, 3, 10, hour: 12)),
      entry(date(2023, 12, 31)),
      entry(date(2024, 3, 11, hour: 15)),
      entry(date(2024, 3, 5)),
      entry(date(2024, 2, 29)),
      entry(date(2024, 3, 10), words: 0, recordingSeconds: 200),
      entry(date(2024, 1, 1)),
      entry(date(2024, 3, 4)),
      entry(date(2024, 3, 11)),
    ]
    let week = ActivityRange.week.buckets(days: days, now: now)
    precondition(week.count == 7 && week.first?.date == date(2024, 3, 5))
    precondition(week.map(\.dictations) == [1, 0, 0, 0, 0, 2, 1])
    precondition(
      week[5].words == 55 && week[5].recordingSeconds == 220 && week[5].savedSeconds == 0)
    let year = ActivityRange.year.buckets(days: days, now: now)
    precondition(year.map(\.date) == [date(2024, 1, 1), date(2024, 2, 1), date(2024, 3, 1)])
    precondition(year.map(\.dictations) == [1, 1, 5])
    let all = ActivityRange.all.buckets(days: days, now: now)
    precondition(all.map(\.dictations) == [1, 1, 1, 5])
    precondition(ActivityRange.month.buckets(days: days, now: now).count == 30)
    precondition(ActivityRange.week.totals(days: days, now: now).dictations == 4)
    for range in ActivityRange.allCases {
      let quiet = range.buckets(days: [], now: now)
      precondition(!quiet.isEmpty && quiet.allSatisfy { $0.words == 0 && $0.dictations == 0 })
      let future = range.buckets(days: [entry(date(2025, 1, 1))], now: now)
      precondition(future.allSatisfy { $0.dictations == 0 })
    }
  }
}
