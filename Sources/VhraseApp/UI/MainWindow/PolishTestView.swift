// Previews Refine or the selected Restyle style on the five most recent dictations, with one batch action and expandable full text; Polishing shows it only once History has entries.

import SwiftUI

struct PolishTestView: View {
  @ObservedObject var appState: AppState
  let operation: PolishOperation
  @StateObject private var test = PolishTest()
  @State private var expanded: Set<UUID> = []

  private var items: [TranscriptHistoryItem] { PolishTest.recentHistory(appState.history) }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .center, spacing: 16) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Recent dictations")
            .font(VhraseFont.headline)
          Text("Newest first · \(appState.settings.adjustmentModel)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
        Spacer(minLength: 8)
        if test.state.isRunning {
          ProgressView().controlSize(.small)
          Text("\(test.state.completedCount) / \(items.count)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
          Button("Cancel") { test.cancel() }
            .buttonStyle(.borderless)
        } else {
          Button("Try all \(items.count)") {
            test.start(
              history: appState.history, operation: operation, settings: appState.settings,
              client: LLMAdjustmentClient(
                apiKey: appState.credentials.effectiveValue(.llmAPIKey),
                baseURL: appState.effectiveLLMBaseURL))
          }
          .buttonStyle(.bordered)
        }
      }

      if case .failed(let message) = test.state {
        Text(message)
          .font(.caption)
          .foregroundStyle(VhraseTheme.statusFailure)
          .textSelection(.enabled)
      }

      VStack(spacing: 0) {
        HStack(spacing: 12) {
          Color.clear.frame(width: 16, height: 0)
          Text("Input").frame(maxWidth: .infinity, alignment: .leading)
          Color.clear.frame(width: 12, height: 0)
          Text("Result").frame(maxWidth: .infinity, alignment: .leading)
          Color.clear.frame(width: 18, height: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.bottom, 4)

        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
          comparisonRow(item, number: index + 1)
          if index < items.count - 1 {
            VhraseTheme.hairline.frame(height: 1)
          }
        }
      }

      Text("Each try uses your LLM allowance. No screenshot, paste, or History changes.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .onChange(of: items.map(\.id)) { _, ids in
      test.clear()
      expanded.formIntersection(ids)
    }
    .onChange(of: appState.settings) { _, _ in test.clear() }
    .onDisappear { test.clear() }
  }

  private func comparisonRow(_ item: TranscriptHistoryItem, number: Int) -> some View {
    let isExpanded = expanded.contains(item.id)
    return HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text("\(number)")
        .font(.caption.monospacedDigit())
        .foregroundStyle(.tertiary)
        .frame(width: 16, alignment: .leading)
        .help(item.createdAt.formatted(date: .abbreviated, time: .shortened))
      Text(item.polishInput)
        .accessibilityLabel("Input: \(item.polishInput)")
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
      Image(systemName: "arrow.right")
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .frame(width: 12)
        .accessibilityHidden(true)
      result(for: item.id)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button {
        if isExpanded { expanded.remove(item.id) } else { expanded.insert(item.id) }
      } label: {
        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .frame(width: 18, height: 22)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(isExpanded ? "Collapse full text" : "Show full input and result")
      .accessibilityLabel("\(isExpanded ? "Collapse" : "Expand") dictation \(number)")
    }
    .font(VhraseFont.transcriptBody)
    .lineLimit(isExpanded ? nil : 3)
    .textSelection(.enabled)
    .fixedSize(horizontal: false, vertical: true)
    .padding(.vertical, 12)
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder
  private func result(for id: UUID) -> some View {
    switch test.state.outcomes[id] {
    case .completed(let result):
      Text(result.output).accessibilityLabel("Result: \(result.output)")
    case .failed(let message):
      Text("Failed: \(message)").font(.caption).foregroundStyle(VhraseTheme.statusFailure)
    case .running:
      Text(operation == .refine ? "Refining…" : "Restyling…").font(.caption)
        .foregroundStyle(.secondary)
    case .cancelled:
      Text("Cancelled").font(.caption).foregroundStyle(.secondary)
    case nil:
      Text("—").foregroundStyle(.tertiary)
    }
  }
}
