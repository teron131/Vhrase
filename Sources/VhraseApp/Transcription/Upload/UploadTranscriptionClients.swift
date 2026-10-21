// Translates recorded WAV audio into each provider's native request and returns one common transcript contract.

import Foundation

final class XAITranscriptionClient: SpeechToTextClient {
  private let apiKey: String

  init(apiKey: String) {
    self.apiKey = apiKey
  }

  func transcribe(fileURL: URL, settings: DictationSettings) async throws -> TranscriptionResult {
    guard !apiKey.isEmpty else {
      throw MissingAPIKeyError(name: "XAI_API_KEY")
    }
    let text = try await uploadForm(
      fields: XAITranscriptionContract.uploadFields(settings: settings),
      fileURL: fileURL,
      to: URL(string: "https://api.x.ai/v1/stt")!,
      authorization: ("Authorization", "Bearer \(apiKey)"),
      timeout: 10,
      providerName: "xAI"
    )
    return TranscriptionResult(text: text, providerName: "xAI")
  }
}

final class ElevenLabsTranscriptionClient: SpeechToTextClient {
  private let apiKey: String

  init(apiKey: String) {
    self.apiKey = apiKey
  }

  func transcribe(fileURL: URL, settings: DictationSettings) async throws -> TranscriptionResult {
    guard !apiKey.isEmpty else {
      throw MissingAPIKeyError(name: "ELEVENLABS_API_KEY")
    }
    let text = try await uploadForm(
      fields: ElevenLabsTranscriptionContract.uploadFields(settings: settings),
      fileURL: fileURL,
      to: URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!,
      authorization: ("xi-api-key", apiKey),
      timeout: 60,
      providerName: "ElevenLabs"
    )
    return TranscriptionResult(text: text, providerName: "ElevenLabs")
  }
}

final class GeminiTranscriptionClient: SpeechToTextClient {
  private let apiKey: String

  init(apiKey: String) { self.apiKey = apiKey }

  /// Submits one non-stored native interaction and rejects incomplete responses before insertion.
  func transcribe(fileURL: URL, settings: DictationSettings) async throws -> TranscriptionResult {
    guard !apiKey.isEmpty else { throw MissingAPIKeyError(name: "GEMINI_API_KEY") }
    var request = URLRequest(
      url: URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions")!)
    request.httpMethod = "POST"
    request.timeoutInterval = 90
    request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try GeminiTranscriptionContract.requestBody(
      audio: Data(contentsOf: fileURL), settings: settings)
    let data = try await perform(request, providerName: "Gemini")
    let response = try JSONDecoder().decode(GeminiTranscriptionResponse.self, from: data)
    guard response.status == "completed" else {
      throw UploadTranscriptionError.incompleteResponse(providerName: "Gemini")
    }
    let text = response.text
    guard !text.isEmpty else {
      throw UploadTranscriptionError.incompleteResponse(providerName: "Gemini")
    }
    return TranscriptionResult(
      text: text,
      providerName: settings.geminiSmartTranscription ? "Gemini · Smart" : "Gemini")
  }
}

final class OpenAITranscriptionClient: SpeechToTextClient {
  private let apiKey: String

  init(apiKey: String) {
    self.apiKey = apiKey
  }

  func transcribe(fileURL: URL, settings: DictationSettings) async throws -> TranscriptionResult {
    guard !apiKey.isEmpty else {
      throw MissingAPIKeyError(name: "OPENAI_API_KEY")
    }
    let text = try await uploadForm(
      fields: OpenAITranscriptionContract.uploadFields(settings: settings),
      fileURL: fileURL,
      to: URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
      authorization: ("Authorization", "Bearer \(apiKey)"),
      timeout: 60,
      providerName: "OpenAI"
    )
    return TranscriptionResult(text: text, providerName: "OpenAI")
  }
}

final class VercelTranscriptionClient: SpeechToTextClient {
  private let apiKey: String

  init(apiKey: String) {
    self.apiKey = apiKey
  }

  /// Sends the recording to whichever gateway model the settings name; the gateway forwards no vocabulary or language hint.
  func transcribe(fileURL: URL, settings: DictationSettings) async throws -> TranscriptionResult {
    guard !apiKey.isEmpty else {
      throw MissingAPIKeyError(name: "AI_GATEWAY_API_KEY")
    }

    var request = URLRequest(url: VercelTranscriptionContract.endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = 60
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    for (name, value) in try VercelTranscriptionContract.headers(settings: settings) {
      request.setValue(value, forHTTPHeaderField: name)
    }
    request.httpBody = try VercelTranscriptionContract.requestBody(
      audio: Data(contentsOf: fileURL))

    let data = try await perform(request, providerName: "Vercel AI Gateway")
    let response = try JSONDecoder().decode(TextTranscriptionResponse.self, from: data)
    return TranscriptionResult(text: response.text, providerName: "Vercel")
  }
}

/// The response shape xAI, ElevenLabs, OpenAI, and Vercel AI Gateway share: a top-level transcript.
private struct TextTranscriptionResponse: Decodable {
  let text: String
}

private struct GeminiTranscriptionResponse: Decodable {
  let status: String
  let steps: [Step]

  var text: String {
    steps.filter { $0.type == "model_output" }
      .flatMap(\.content)
      .filter { $0.type == "text" }
      .compactMap(\.text)
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  struct Step: Decodable {
    let type: String
    let content: [Content]
  }

  struct Content: Decodable {
    let type: String
    let text: String?
  }
}

private func uploadForm(
  fields: [(String, String)],
  fileURL: URL,
  to url: URL,
  authorization: (header: String, value: String),
  timeout: TimeInterval,
  providerName: String
) async throws -> String {
  let form = try MultipartForm(
    fields: fields, fileField: "file", fileURL: fileURL, mimeType: "audio/wav")
  var request = URLRequest(url: url)
  request.httpMethod = "POST"
  request.timeoutInterval = timeout
  request.setValue(authorization.value, forHTTPHeaderField: authorization.header)
  request.setValue(
    "multipart/form-data; boundary=\(form.boundary)", forHTTPHeaderField: "Content-Type")
  request.httpBody = form.body
  let data = try await perform(request, providerName: providerName)
  return try JSONDecoder().decode(TextTranscriptionResponse.self, from: data).text
}

private func perform(
  _ request: URLRequest,
  providerName: String
) async throws -> Data {
  let (data, response) = try await URLSession.shared.data(for: request)
  guard let http = response as? HTTPURLResponse else {
    return data
  }
  guard (200..<300).contains(http.statusCode) else {
    let responseText = String(data: data, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let fallback = HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
    let responseDetail = responseText.flatMap { $0.isEmpty ? nil : $0 } ?? fallback
    let detail = String(responseDetail.prefix(1_000))
    throw UploadTranscriptionError.httpFailure(
      providerName: providerName,
      statusCode: http.statusCode,
      detail: detail
    )
  }
  return data
}

private enum UploadTranscriptionError: LocalizedError {
  case httpFailure(providerName: String, statusCode: Int, detail: String)
  case incompleteResponse(providerName: String)

  var errorDescription: String? {
    switch self {
    case .httpFailure(let providerName, let statusCode, let detail):
      "\(providerName) transcription failed with HTTP \(statusCode): \(detail)"
    case .incompleteResponse(let providerName):
      "\(providerName) returned no completed transcript. Try recording again."
    }
  }
}
