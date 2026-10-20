// Groups local activity by the selected calendar range; each period total is a tile that also chooses what the chart plots.

import Charts
import SwiftUI

/// Every activity total can be charted, so choosing a total and choosing the plotted series are one action.
enum ActivityMetric: String, CaseIterable, Identifiable {
  case dictations = "Dictations"
  case words = "Words"
  case rate = "Dictation rate"
  case saved = "Est. time saved"
  case cost = "Est. cost"

  var id: Self { self }

  var detail: String {
    switch self {
    case .dictations: "completed"
    case .words: "dictated"
    case .rate: "while recording"
    case .saved: "vs. typing at 55 WPM"
    case .cost: "transcription only"
    }
  }

  var explanation: String? {
    switch self {
    case .dictations, .words:
      nil
    case .rate:
      "Words dictated per minute of recording."
    case .saved:
      "Compared with typing at 55 words per minute, subtracting recording and all processing time. Language-aware word counts and time saved are estimates."
    case .cost:
      "List-price estimate for completed dictations since tracking began. Excludes cleanup, failed requests, subscriptions, and free-tier credits. Gemini uses an approximate per-minute rate."
    }
  }

  func value(_ day: DictationActivityDay) -> Double {
    switch self {
    case .dictations: Double(day.dictations)
    case .words: Double(day.words)
    case .rate: day.dictatedWordsPerMinute
    case .saved: day.savedSeconds / 60
    case .cost: day.estimatedCostUSD
    }
  }

  func label(_ day: DictationActivityDay) -> String {
    switch self {
    case .dictations: day.dictations.formatted()
    case .words: day.words.formatted()
    case .rate: "\(Int(day.dictatedWordsPerMinute.rounded()).formatted()) WPM"
    case .saved: Self.duration(day.savedSeconds)
    case .cost: Self.cost(day.estimatedCostUSD)
    }
  }

  private static func duration(_ seconds: Double) -> String {
    let wholeSeconds = Int(seconds)
    if wholeSeconds < 60 { return "\(wholeSeconds)s" }
    if wholeSeconds < 3_600 { return "\(wholeSeconds / 60)m \(wholeSeconds % 60)s" }
    return "\(wholeSeconds / 3_600)h \(wholeSeconds % 3_600 / 60)m"
  }

  private static func cost(_ dollars: Double) -> String {
    if dollars > 0 && dollars < 0.01 { return "<$0.01" }
    return dollars.formatted(.currency(code: "USD"))
  }
}

struct DictationActivityChart: View {
  let days: [DictationActivityDay]
  let now: Date
  let range: ActivityRange
  @Binding var metric: ActivityMetric
  @State private var hoveredDate: Date?

  var body: some View {
    let buckets = range.buckets(days: days, now: now)
    let totals = range.totals(days: days, now: now)

    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 10) {
        ForEach(ActivityMetric.allCases) { item in
          metricTab(item, totals: totals)
        }
      }

      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 8) {
          SeriesSwatch()
          Text("\(metric.rawValue) \(range.component == .day ? "per day" : "per month")")
            .font(VhraseFont.pill)
            .foregroundStyle(.secondary)
        }
        .frame(height: 18)
        .accessibilityElement(children: .combine)

        chart(buckets)
          .frame(height: 200)

        if buckets.allSatisfy({ $0.dictations == 0 }) {
          Text("No dictations in this period.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .padding(18)
      .surface()
    }
    .onChange(of: range) { _, _ in hoveredDate = nil }
    .onChange(of: metric) { _, _ in hoveredDate = nil }
  }

  /// Presents one period total as a tile; the selected total fills with the accent and is the series drawn below.
  private func metricTab(_ item: ActivityMetric, totals: DictationActivityDay) -> some View {
    let isSelected = metric == item
    return Button {
      metric = item
    } label: {
      StatTile(
        value: item.label(totals), title: item.rawValue, detail: item.detail,
        isSelected: isSelected)
    }
    .buttonStyle(PressableButtonStyle(pressedScale: 0.95))
    .help(item.explanation ?? "Chart \(item.rawValue.lowercased())")
    .accessibilityLabel("\(item.rawValue), \(item.label(totals)) \(item.detail)")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityHint("Shows this total in the chart")
  }

  private func chart(_ buckets: [DictationActivityDay]) -> some View {
    let selected = hoveredDate.flatMap { date in buckets.first { $0.date == date } }
    let first = buckets.first?.date ?? now
    let last = buckets.last?.date ?? now
    let end =
      last > first ? last : Calendar.current.date(byAdding: range.component, value: 1, to: first)!

    return Chart {
      ForEach(buckets, id: \.date) { day in
        AreaMark(x: .value("Date", day.date), y: .value(metric.rawValue, metric.value(day)))
          .interpolationMethod(.monotone)
          .foregroundStyle(
            LinearGradient(
              colors: [VhraseTheme.accent.opacity(0.28), VhraseTheme.accent.opacity(0.02)],
              startPoint: .top, endPoint: .bottom)
          )
          .accessibilityHidden(true)
        LineMark(x: .value("Date", day.date), y: .value(metric.rawValue, metric.value(day)))
          .interpolationMethod(.monotone)
          .lineStyle(StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
          .foregroundStyle(VhraseTheme.accent)
          .accessibilityLabel(dateLabel(day.date))
          .accessibilityValue("\(metric.rawValue): \(metric.label(day))")
        PointMark(x: .value("Date", day.date), y: .value(metric.rawValue, metric.value(day)))
          .symbol { PointDot(diameter: 9) }
          .accessibilityHidden(true)
      }
      if let selected, let index = buckets.firstIndex(where: { $0.date == selected.date }) {
        RuleMark(x: .value("Date", selected.date))
          .foregroundStyle(VhraseTheme.accent.opacity(0.5))
          .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
          .accessibilityHidden(true)
        // The breakdown opens toward the wider side of the plot so it never covers the point it describes.
        PointMark(
          x: .value("Date", selected.date), y: .value(metric.rawValue, metric.value(selected))
        )
        .symbol { PointDot(diameter: 14, isFilled: true) }
        .annotation(
          position: index * 2 < buckets.count ? .trailing : .leading, spacing: 12,
          overflowResolution: .init(x: .fit(to: .plot), y: .fit(to: .plot))
        ) {
          breakdown(selected)
        }
        .accessibilityHidden(true)
      }
    }
    // Padding leaves room for the end points and their centered date labels.
    .chartXScale(domain: first...end, range: .plotDimension(padding: 24))
    .chartYScale(
      domain:
        0...max(metric == .cost ? 0.01 : 1, (buckets.map { metric.value($0) }.max() ?? 0) * 1.1)
    )
    .chartXAxis {
      AxisMarks(values: range == .week ? .stride(by: .day) : .automatic(desiredCount: 6)) { value in
        AxisValueLabel(anchor: .top) {
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
  }

  /// Lists every total for one period, so the quiet days the line flattens can still be read; the charted total carries the legend swatch.
  private func breakdown(_ day: DictationActivityDay) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(dateLabel(day.date))
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 5) {
        ForEach(ActivityMetric.allCases) { item in
          let isCharted = item == metric
          GridRow {
            SeriesSwatch().opacity(isCharted ? 1 : 0)
            Text(item.rawValue)
              .foregroundStyle(isCharted ? .primary : .secondary)
            Text(item.label(day))
              .monospacedDigit()
              .fontWeight(isCharted ? .bold : .medium)
              .foregroundStyle(isCharted ? VhraseTheme.accent : .primary)
              .gridColumnAlignment(.trailing)
          }
        }
      }
      .font(.callout)
    }
    .padding(12)
    .fixedSize()
    .surface(cornerRadius: VhraseTheme.fieldCornerRadius)
    .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
  }

  private func dateLabel(_ date: Date) -> String {
    range.component == .month
      ? date.formatted(.dateTime.month(.wide).year())
      : date.formatted(date: .abbreviated, time: .omitted)
  }
}

/// The legend key for the plotted series: a stroke of the line with the point marker on it.
private struct SeriesSwatch: View {
  var body: some View {
    Capsule()
      .fill(VhraseTheme.accent)
      .frame(width: 18, height: 3.5)
      .overlay { PointDot(diameter: 9) }
  }
}

/// Marks one period's value: hollow on the line, filled for the hovered period.
private struct PointDot: View {
  let diameter: CGFloat
  var isFilled = false

  var body: some View {
    Circle()
      .fill(isFilled ? VhraseTheme.accent : VhraseTheme.card)
      .overlay {
        Circle().strokeBorder(isFilled ? VhraseTheme.card : VhraseTheme.accent, lineWidth: 2.5)
      }
      .frame(width: diameter, height: diameter)
  }
}
