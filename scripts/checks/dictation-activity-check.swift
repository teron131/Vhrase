// Verifies duration-weighted dictation rates and nonnegative aggregate time savings.

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

    print("dictation activity metrics ok")
  }
}
