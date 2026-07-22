// Exercises Vhrase's upload STT providers with environment overrides or saved Keychain credentials.

import Foundation
import Security

enum SmokeError: LocalizedError {
    case missingArgument(String)
    case unknownArgument(String)
    case missingKey(String)
    case badProvider(String)
    case badResponse(String)
    case keychain(String)
    case emptyTranscript
    case expectationFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .missingArgument(let name):
            "Missing value for \(name)."
        case .unknownArgument(let name):
            "Unknown argument: \(name)."
        case .missingKey(let name):
            "\(name) is missing. Export it or save it in the Vhrase Keychain first."
        case .badProvider(let name):
            "Unknown provider: \(name). Use xai or elevenlabs."
        case .badResponse(let message):
            message
        case .keychain(let message):
            "Could not read the Vhrase Keychain credential: \(message)"
        case .emptyTranscript:
            "Provider returned an empty transcript."
        case .expectationFailed(let expected, let actual):
            "Transcript did not include expected text '\(expected)'. Transcript: \(actual)"
        }
    }
}

enum Provider: String {
    case xai
    case elevenLabs = "elevenlabs"

    var keyName: String {
        switch self {
        case .xai:
            "XAI_API_KEY"
        case .elevenLabs:
            "ELEVENLABS_API_KEY"
        }
    }
}

struct Options {
    var provider: Provider?
    var audioPath = ""
    var language = "en"
    var elevenLabsNoVerbatim = false
    var keyterms: [String] = []
    var expect: String?
    var verbose = false
}

struct MultipartForm {
    let boundary: String
    let body: Data

    init(
        fields: [(String, String)],
        fileField: String,
        fileURL: URL,
        mimeType: String
    ) throws {
        boundary = "Boundary-\(UUID().uuidString)"
        var data = Data()

        for (name, value) in fields {
            data.append("--\(boundary)\r\n")
            data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            data.append("\(value)\r\n")
        }

        data.append("--\(boundary)\r\n")
        data.append("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
        data.append("Content-Type: \(mimeType)\r\n\r\n")
        data.append(try Data(contentsOf: fileURL))
        data.append("\r\n--\(boundary)--\r\n")
        body = data
    }
}

struct STTResponse: Decodable {
    let text: String
    let duration: Double?
}

@main
struct LiveSTTSmoke {
    static func main() async {
        do {
            let options = try parseOptions()
            guard let provider = options.provider else {
                throw SmokeError.missingArgument("--provider")
            }
            guard !options.audioPath.isEmpty else {
                throw SmokeError.missingArgument("--audio")
            }

            let key = try keyValue(for: provider.keyName)
            guard !key.isEmpty else {
                throw SmokeError.missingKey(provider.keyName)
            }

            let audioURL = URL(fileURLWithPath: options.audioPath)
            let result = try await transcribe(
                provider: provider,
                apiKey: key,
                audioURL: audioURL,
                options: options
            )
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw SmokeError.emptyTranscript
            }
            if let expect = options.expect, !text.localizedCaseInsensitiveContains(expect) {
                throw SmokeError.expectationFailed(expect, text)
            }

            print("Provider: \(provider.rawValue)")
            print("Mode: upload")
            print("Transcript: \(text)")
            if let duration = result.duration {
                print(String(format: "Duration: %.2fs", duration))
            }
        } catch {
            fputs("live-stt-smoke: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func parseOptions() throws -> Options {
        var options = Options()
        var args = Array(CommandLine.arguments.dropFirst())

        while !args.isEmpty {
            let arg = args.removeFirst()
            switch arg {
            case "--provider":
                let value = try takeValue(&args, for: arg)
                guard let provider = Provider(rawValue: value) else {
                    throw SmokeError.badProvider(value)
                }
                options.provider = provider
            case "--audio":
                options.audioPath = try takeValue(&args, for: arg)
            case "--language":
                options.language = try takeValue(&args, for: arg)
            case "--elevenlabs-no-verbatim":
                options.elevenLabsNoVerbatim = true
            case "--keyterm":
                options.keyterms.append(try takeValue(&args, for: arg))
            case "--expect":
                options.expect = try takeValue(&args, for: arg)
            case "--verbose":
                options.verbose = true
            case "--help", "-h":
                print("Usage: live-stt-smoke --provider xai|elevenlabs --audio path.wav [--language en] [--keyterm term] [--elevenlabs-no-verbatim] [--expect text] [--verbose]")
                exit(0)
            default:
                throw SmokeError.unknownArgument(arg)
            }
        }

        return options
    }

    private static func takeValue(
        _ args: inout [String],
        for name: String
    ) throws -> String {
        guard !args.isEmpty else {
            throw SmokeError.missingArgument(name)
        }
        return args.removeFirst()
    }

    /// Reads a nonempty environment override before the generic-password item saved by Vhrase.
    private static func keyValue(for name: String) throws -> String {
        if let value = ProcessInfo.processInfo.environment[name], !value.isEmpty {
            return value
        }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "Vhrase",
            kSecAttrAccount: name,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return ""
        }
        guard status == errSecSuccess else {
            let message = (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
            throw SmokeError.keychain(message)
        }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw SmokeError.keychain("Keychain returned invalid credential data.")
        }
        return value
    }

    private static func transcribe(
        provider: Provider,
        apiKey: String,
        audioURL: URL,
        options: Options
    ) async throws -> STTResponse {
        switch provider {
        case .xai:
            return try await transcribeXAIUpload(apiKey: apiKey, audioURL: audioURL, options: options)
        case .elevenLabs:
            return try await transcribeElevenLabsUpload(apiKey: apiKey, audioURL: audioURL, options: options)
        }
    }

    private static func transcribeXAIUpload(
        apiKey: String,
        audioURL: URL,
        options: Options
    ) async throws -> STTResponse {
        var fields = [
            ("format", "true"),
            ("language", options.language),
        ]
        fields += options.keyterms.map { ("keyterm", $0) }
        let form = try MultipartForm(
            fields: fields,
            fileField: "file",
            fileURL: audioURL,
            mimeType: mimeType(for: audioURL)
        )
        var request = URLRequest(url: URL(string: "https://api.x.ai/v1/stt")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(form.boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.body
        return try await perform(request, options: options)
    }

    private static func transcribeElevenLabsUpload(
        apiKey: String,
        audioURL: URL,
        options: Options
    ) async throws -> STTResponse {
        var fields = [
            ("model_id", "scribe_v2"),
            ("no_verbatim", options.elevenLabsNoVerbatim ? "true" : "false"),
        ]
        if !options.language.isEmpty {
            fields.append(("language_code", options.language))
        }
        fields += options.keyterms.map { ("keyterms", $0) }
        let form = try MultipartForm(
            fields: fields,
            fileField: "file",
            fileURL: audioURL,
            mimeType: mimeType(for: audioURL)
        )
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("multipart/form-data; boundary=\(form.boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.body
        return try await perform(request, options: options)
    }

    private static func perform(
        _ request: URLRequest,
        options: Options
    ) async throws -> STTResponse {
        log("POST \(request.url?.absoluteString ?? "unknown URL")", options)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SmokeError.badResponse("No HTTP response.")
        }
        log("HTTP \(http.statusCode)", options)
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw SmokeError.badResponse("HTTP \(http.statusCode): \(message)")
        }
        return try JSONDecoder().decode(STTResponse.self, from: data)
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "wav":
            "audio/wav"
        case "mp3":
            "audio/mpeg"
        case "m4a":
            "audio/mp4"
        case "aiff", "aif":
            "audio/aiff"
        default:
            "application/octet-stream"
        }
    }

    private static func log(_ message: String, _ options: Options) {
        guard options.verbose else {
            return
        }
        fputs("[live-stt-smoke] \(message)\n", stderr)
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
