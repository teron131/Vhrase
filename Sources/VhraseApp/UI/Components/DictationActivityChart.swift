// Groups local activity by the selected calendar range and displays daily or monthly usage as an interactive area chart.

import Charts
import SwiftUI

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
    var date = start(days: days, now: now)
    var result: [DictationActivityDay] = []
    while date <= now {
      guard let next = calendar.date(byAdding: component, value: 1, to: date) else { break }
      let total = days.reduce(into: DictationActivityDay(date: date)) { total, day in
        if day.date >= date && day.date < next && day.date <= now { total.add(day) }
      }
      result.append(total)
      date = next
    }
    return result
  }
}

private enum ActivityChartMetric: String, CaseIterable {
  case words = "Words"
  case rate = "Dictation rate"
  case dictations = "Dictations"
  case saved = "Est. time saved"

  func value(_ day: DictationActivityDay) -> Double {
    switch self {
    case .words: Double(day.words)
    case .rate: day.dictatedWordsPerMinute
    case .dictations: Double(day.dictations)
    case .saved: day.savedSeconds / 60
    }
  }

  func label(_ day: DictationActivityDay) -> String {
    let number = value(day).formatted(.number.precision(.fractionLength(0...1)))
    switch self {
    case .rate: return "\(number) WPM"
    case .saved: return "\(number) min"
    case .words, .dictations: return number
    }
  }
}

struct DictationActivityChart: View {
  let days: [DictationActivityDay]
  let now: Date
  let range: ActivityRange
  @State private var metric = ActivityChartMetric.words
  @State private var hoveredDate: Date?

  var body: some View {
    let buckets = range.buckets(days: days, now: now)
    let totals = range.totals(days: days, now: now)
    let selected = hoveredDate.flatMap { date in buckets.first { $0.date == date } }
    let first = buckets.first?.date ?? now
    let last = buckets.last?.date ?? now
    let end =
      last > first ? last : Calendar.current.date(byAdding: range.component, value: 1, to: first)!

    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 8) {
          Picker("Chart metric", selection: $metric) {
            ForEach(ActivityChartMetric.allCases, id: \.self) { item in
              Text(item.rawValue).tag(item)
            }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .frame(width: 480)
          Text(metric.label(totals))
            .font(.system(size: 30, weight: .medium, design: .rounded).monospacedDigit())
          Text("\(range.rawValue) · \(range.component == .day ? "Daily" : "Monthly")")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        if let selected {
          VStack(alignment: .trailing, spacing: 6) {
            Text(dateLabel(selected.date))
              .font(.caption)
              .foregroundStyle(.secondary)
            Text(metric.label(selected))
              .font(.callout.weight(.semibold).monospacedDigit())
              .foregroundStyle(VhraseTheme.accent)
          }
          .accessibilityElement(children: .combine)
        }
      }

      Chart {
        ForEach(buckets, id: \.date) { day in
          AreaMark(x: .value("Date", day.date), y: .value(metric.rawValue, metric.value(day)))
            .interpolationMethod(.monotone)
            .foregroundStyle(
              LinearGradient(
                colors: [VhraseTheme.accent.opacity(0.5), VhraseTheme.accent.opacity(0.06)],
                startPoint: .top, endPoint: .bottom)
            )
            .accessibilityHidden(true)
          LineMark(x: .value("Date", day.date), y: .value(metric.rawValue, metric.value(day)))
            .interpolationMethod(.monotone)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .foregroundStyle(VhraseTheme.accent)
            .accessibilityLabel(dateLabel(day.date))
            .accessibilityValue("\(metric.rawValue): \(metric.label(day))")
          if buckets.count == 1 || selected?.date == day.date {
            PointMark(x: .value("Date", day.date), y: .value(metric.rawValue, metric.value(day)))
              .foregroundStyle(VhraseTheme.accent)
              .symbolSize(35)
              .accessibilityHidden(true)
          }
        }
        if let selected {
          RuleMark(x: .value("Date", selected.date))
            .foregroundStyle(VhraseTheme.accent.opacity(0.5))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .accessibilityHidden(true)
        }
      }
      .chartXScale(domain: first...end)
      .chartYScale(domain: 0...max(1, (buckets.map { metric.value($0) }.max() ?? 0) * 1.1))
      .chartXAxis {
        AxisMarks(values: .automatic(desiredCount: 6)) { value in
          AxisValueLabel {
            if let date = value.as(Date.self) {
              Text(
                date.formatted(
                  range.component == .day
                    ? .dateTime.month(.abbreviated).day()
                    : .dateTime.month(.abbreviated).year(.twoDigits)))
            }
          }
        }
      }
      .chartYAxis {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
          AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
            .foregroundStyle(VhraseTheme.inkSecondary.opacity(0.2))
          AxisValueLabel()
        }
      }
      .chartOverlay { proxy in
        GeometryReader { geometry in
          Rectangle().fill(.clear).contentShape(Rectangle())
            .onContinuousHover { phase in
              switch phase {
              case .active(let location):
                guard let plotFrame = proxy.plotFrame else {
                  hoveredDate = nil
                  return
                }
                let plot = geometry[plotFrame]
                guard plot.contains(location),
                  let date: Date = proxy.value(atX: location.x - plot.minX)
                else {
                  hoveredDate = nil
                  return
                }
                hoveredDate =
                  buckets.min {
                    abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                  }?.date
              case .ended:
                hoveredDate = nil
              }
            }
        }
      }
      .frame(height: 210)
      .onChange(of: range) { _, _ in hoveredDate = nil }
      .onChange(of: metric) { _, _ in hoveredDate = nil }

      if buckets.allSatisfy({ $0.dictations == 0 }) {
        Text("No dictations in this period")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func dateLabel(_ date: Date) -> String {
    range.component == .month
      ? date.formatted(.dateTime.month(.wide).year())
      : date.formatted(date: .abbreviated, time: .omitted)
  }
}
