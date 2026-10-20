// Owns the one vocabulary list and shows how each stage reads it: as recognition hints within the provider's limits, and as spelling references for polishing.

import SwiftUI

struct VocabularyView: View {
  @ObservedObject var appState: AppState
  let navigation: MainWindowNavigation

  private var settings: DictationSettings { appState.settings }

  var body: some View {
    mainWindowPage {
      pageHeader(
        "Vocabulary",
        description:
          "Names and jargon Vhrase should get right, shared by transcription and refinement."
      )

      settingsGroup {
        VocabularyEditor(appState: appState)
          .settingsRowStyle()
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Where it's used")
          .font(VhraseFont.headline)
          .accessibilityAddTraits(.isHeader)
        HStack(alignment: .top, spacing: 10) {
          transcriptionUse
          refinementUse
        }
      }
    }
    .disabled(appState.presentation.workflowControlsAreDisabled)
    .mainWindowEvents(appState: appState)
  }

  private var transcriptionUse: some View {
    let provider = settings.provider
    let count = settings.keytermList.count
    let limit = TranscriptionContract.maximumKeyterms(
      provider: provider, mode: settings.transcriptionMode)
    return UseCard(
      stage: .transcription,
      source: "\(provider.title) · \(settings.transcriptionModeTitle)",
      role: provider.takesVocabularyHints ? "Sent as recognition hints" : "Not sent",
      isActive: provider.takesVocabularyHints,
      detail: settings.vocabularyHintGuidance,
      open: { navigation.open(.transcription) },
      meter: {
        if provider.takesVocabularyHints, let limit {
          CapacityBar(count: count, limit: limit)
        }
      }
    )
  }

  private var refinementUse: some View {
    let model = settings.adjustmentModel.trimmingCharacters(in: .whitespacesAndNewlines)
    return UseCard(
      stage: .refinement,
      source: model.isEmpty ? "No model chosen" : model,
      role: settings.adjustWithLLM ? "Spelling reference" : "Double-tap polishing only",
      isActive: settings.adjustWithLLM,
      detail: settings.adjustWithLLM
        ? "The model uses these to spell names and jargon correctly; it never adds them on its own."
        : "Automatic polishing is off, so only text you double-tap to polish uses these.",
      open: { navigation.open(.refinement) },
      meter: { EmptyView() }
    )
  }
}

private struct UseCard<Meter: View>: View {
  let stage: MainWindowTab
  let source: String
  let role: String
  let isActive: Bool
  let detail: String
  let open: () -> Void
  @ViewBuilder let meter: () -> Meter

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Image(systemName: stage.systemImage)
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(VhraseTheme.inkSecondary)
          .frame(width: 24, height: 24)
          .background(Circle().fill(VhraseTheme.field))
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 0) {
          Text(stage.title)
            .font(VhraseFont.headline)
          Text(source)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
        Spacer(minLength: 8)
        Button("Open", action: open)
          .buttonStyle(AccentLinkButtonStyle())
          .font(.callout)
          .accessibilityLabel("Open \(stage.title)")
      }

      Text(role)
        .font(VhraseFont.title)
        .foregroundStyle(isActive ? Color.primary : Color.secondary)

      meter()

      Text(detail)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .surface()
    .accessibilityElement(children: .contain)
  }
}

private struct CapacityBar: View {
  let count: Int
  let limit: Int

  var body: some View {
    let isOver = count > limit
    VStack(alignment: .leading, spacing: 4) {
      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          Capsule().fill(VhraseTheme.field)
          Capsule()
            .fill(isOver ? VhraseTheme.statusFailure : VhraseTheme.accent)
            .frame(
              width: count == 0
                ? 0 : max(8, geometry.size.width * min(1, CGFloat(count) / CGFloat(limit))))
        }
      }
      .frame(height: 8)
      Text("\(count) of \(limit.formatted()) terms")
        .font(.caption.monospacedDigit())
        .foregroundStyle(isOver ? VhraseTheme.statusFailure : Color.secondary)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(count) of \(limit) terms used")
  }
}
