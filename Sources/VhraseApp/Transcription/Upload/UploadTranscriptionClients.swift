// Implements upload-based xAI and ElevenLabs speech-to-text provider adapters.

import Foundation

protocol SpeechToTextClient: Sendable {
  func transcribe(fileURL: URL, settings: DictationSettings) async throws -> TranscriptionResult
}

final class XAITranscriptionClient: SpeechToTextClient, @unchecked Sendable {
  private let apiKey: String

  init(apiKey: String) {
    self.apiKey = apiKey
  }

  func transcribe(fileURL: URL, settings: DictationSettings) async throws -> TranscriptionResult {
    guard !apiKey.isEmpty else {
      throw missingKey("XAI_API_KEY")
    }

    let form = try MultipartForm(
      fields: try XAITranscriptionContract.uploadFields(settings: settings),
      fileField: "file",
      fileURL: fileURL,
      mimeType: "audio/wav"
    )

    var request = URLRequest(url: URL(string: "https://api.x.ai/v1/stt")!)
    request.httpMethod = "POST"
    request.timeoutInterval = 60
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue(
      "multipart/form-data; boundary=\(form.boundary)", forHTTPHeaderField: "Content-Type")
    request.httpBody = form.body

    let data = try await perform(request, providerName: "xAI")
    let response = try JSONDecoder().decode(XAITranscriptionResponse.self, from: data)
    return TranscriptionResult(
      text: response.text, providerName: "xAI", duration: response.duration)
  }
}

final class ElevenLabsTranscriptionClient: SpeechToTextClient, @unchecked Sendable {
  private let apiKey: String

  init(apiKey: String) {
    self.apiKey = apiKey
  }

  func transcribe(fileURL: URL, settings: DictationSettings) async throws -> TranscriptionResult {
    guard !apiKey.isEmpty else {
      throw missingKey("ELEVENLABS_API_KEY")
    }

    let form = try MultipartForm(
      fields: try ElevenLabsTranscriptionContract.uploadFields(settings: settings),
      fileField: "file",
      fileURL: fileURL,
      mimeType: "audio/wav"
    )

    var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!)
    request.httpMethod = "POST"
    request.timeoutInterval = 60
    request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
    request.setValue(
      "multipart/form-data; boundary=\(form.boundary)", forHTTPHeaderField: "Content-Type")
    request.httpBody = form.body

    let data = try await perform(request, providerName: "ElevenLabs")
    let response = try JSONDecoder().decode(ElevenLabsTranscriptionResponse.self, from: data)
    return TranscriptionResult(text: response.text, providerName: "ElevenLabs", duration: nil)
  }
}

private struct XAITranscriptionResponse: Decodable {
  let text: String
  let duration: Double?
}

private struct ElevenLabsTranscriptionResponse: Decodable {
  let text: String
}

private func missingKey(_ name: String) -> NSError {
  NSError(
    domain: "Vhrase.STT",
    code: 1,
    userInfo: [
      NSLocalizedDescriptionKey:
        "\(name) is missing. Add it in Settings or export it before launch."
    ]
  )
}

/// Preserves useful provider and HTTP context while keeping response bodies bounded.
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
    let detail = String((responseText?.isEmpty == false ? responseText! : fallback).prefix(1_000))
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

  var errorDescription: String? {
    switch self {
    case .httpFailure(let providerName, let statusCode, let detail):
      "\(providerName) transcription failed with HTTP \(statusCode): \(detail)"
    }
  }
}
