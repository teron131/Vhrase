// Owns calendar ranges and content-free activity aggregation shared by summaries and charts.

import Foundation

enum ActivityRange: String, CaseIterable {
  case week = "7 days"
  case month = "30 days"
  case year = "This year"
  case all = "All time"

  var component: Calendar.Component { self == .week || self == .month ? .day : .month }

  func start(days: [DictationActivityDay], now: Date) -> Date {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: now)
    switch self {
    case .week: return calendar.date(byAdding: .day, value: -6, to: today)!
    case .month: return calendar.date(byAdding: .day, value: -29, to: today)!
    case .year: return calendar.dateInterval(of: .year, for: now)!.start
    case .all:
      return calendar.dateInterval(of: .month, for: min(days.map(\.date).min() ?? today, today))!
        .start
    }
  }

  func totals(days: [DictationActivityDay], now: Date) -> DictationActivityDay {
    let beginning = start(days: days, now: now)
    return days.reduce(into: DictationActivityDay(date: beginning)) { total, day in
      if day.date >= beginning && day.date <= now { total.add(day) }
    }
  }

  /// Fills quiet calendar periods with zeroes and clamps savings only after each period has been aggregated.
  func buckets(days: [DictationActivityDay], now: Date) -> [DictationActivityDay] {
    let calendar = Calendar.current
    let beginning = start(days: days, now: now)
    var date = beginning
    var result: [DictationActivityDay] = []
    while date <= now {
      guard let next = calendar.date(byAdding: component, value: 1, to: date) else { break }
      result.append(DictationActivityDay(date: date))
      date = next
    }
    // Use the actual calendar boundaries, preserving input order within each bucket and avoiding per-day calendar conversions.
    for day in days where day.date >= beginning && day.date <= now {
      var lower = 0
      var upper = result.count
      while lower < upper {
        let middle = (lower + upper) / 2
        if result[middle].date <= day.date {
          lower = middle + 1
        } else {
          upper = middle
        }
      }
      if lower > 0 { result[lower - 1].add(day) }
    }
    return result
  }
}
