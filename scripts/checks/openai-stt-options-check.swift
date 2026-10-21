// Verifies OpenAI's fixed-model upload fields, its keyword policy, and that it stays an after-stop cloud provider.

import Foundation

@main
struct OpenAISTTOptionsCheck {
  static func main() throws {
    var settings = DictationSettings.defaults
    settings.provider = .openAI
    settings.transcriptionMode = .upload
    settings.language = " yue "
    settings.keyterms = " Vercel\nrefactor\nVercel\n\nMonte Carlo"
    precondition(STTProvider.openAI.location == .cloud)
    precondition(STTProvider.openAI.availableModes == [.upload])
    precondition(settings.recognitionLanguage == "yue")

    let fields = try OpenAITranscriptionContract.uploadFields(settings: settings)
    precondition(fields.first! == ("model", "gpt-transcribe"))
    var newerModel = settings
    newerModel.openAIModel = " gpt-transcribe-next "
    let newerFields = try OpenAITranscriptionContract.uploadFields(settings: newerModel)
    precondition(newerFields.first! == ("model", "gpt-transcribe-next"))
    precondition(fields.filter { $0.0 == "languages[]" }.map(\.1) == ["yue"])
    precondition(
      fields.filter { $0.0 == "keywords[]" }.map(\.1) == ["Vercel", "refactor", "Monte Carlo"])
    // GPT Transcribe replaces the singular field, and OpenAI rejects a request that sends both.
    precondition(!fields.contains { $0.0 == "language" })

    settings.language = ""
    settings.keyterms = ""
    let bare = try OpenAITranscriptionContract.uploadFields(settings: settings)
    precondition(bare.map(\.0) == ["model"])

    // No documented count or length limit, so a long list sized for LLM polishing still records.
    settings.keyterms = (1...1_200).map { "term \($0) " + String(repeating: "x", count: 60) }
      .joined(separator: "\n")
    try TranscriptionContract.validate(settings: settings)
    settings.keyterms = "a <b> tag"
    do {
      _ = try OpenAITranscriptionContract.uploadFields(settings: settings)
      preconditionFailure("Accepted a keyword OpenAI rejects")
    } catch {
      precondition(error.localizedDescription.contains("unsupported character '<'"))
    }

    settings.keyterms = "Vercel"
    settings.transcriptionMode = .realtime
    do {
      try TranscriptionContract.validate(settings: settings)
      preconditionFailure("Accepted realtime OpenAI transcription")
    } catch {
      precondition(error.localizedDescription.contains("Upload"))
    }
    print("OpenAI upload fields and keyword policy ok")
  }
}
