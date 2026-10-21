// Prices LLM polishing at the endpoint's published list rates, fetched once per model each session: Vercel AI Gateway's `/models` catalog lists per-token prices, while endpoints that publish none leave polishing uncounted.

import Foundation

struct LLMPrice: Equatable, Sendable {
  let inputPerToken: Double
  let outputPerToken: Double

  /// Charges every input token at the uncached rate, so a request that reuses the provider's prompt cache actually costs less than this.
  func cost(of usage: LLMUsage) -> Double {
    Double(usage.inputTokens) * inputPerToken + Double(usage.outputTokens) * outputPerToken
  }

  /// Finds `model` in a `/models` response, matching a bare name such as `gpt-6-luna` to the gateway's `openai/gpt-6-luna`; `nil` when the model or its prices are not listed.
  static func listed(for model: String, in catalog: Data) throws -> LLMPrice? {
    let models = try JSONDecoder().decode(Catalog.self, from: catalog).data
    guard
      let entry = models.first(where: { $0.id == model })
        ?? models.first(where: { $0.id.hasSuffix("/\(model)") }),
      let input = entry.pricing?.input.flatMap(Double.init),
      let output = entry.pricing?.output.flatMap(Double.init)
    else {
      return nil
    }
    return LLMPrice(inputPerToken: input, outputPerToken: output)
  }
}

/// Fetches an endpoint's catalog only for a model's first polish in a session; an endpoint that lists no price for it is remembered too, so it is not asked again.
@MainActor
final class LLMPriceList {
  private var prices: [String: LLMPrice?] = [:]

  func price(of model: String, at baseURL: String, apiKey: String) async throws -> LLMPrice? {
    let key = "\(baseURL) \(model)"
    if let listed = prices[key] {
      return listed
    }
    let price = try await LLMAdjustmentClient(apiKey: apiKey, baseURL: baseURL).listPrice(
      for: model)
    prices[key] = price
    return price
  }
}

/// OpenAI's own model list has no `pricing`, and some gateway entries price only input, so every price field is optional.
private struct Catalog: Decodable {
  struct Model: Decodable {
    let id: String
    let pricing: Pricing?
  }

  /// Dollars per token, written as decimal strings.
  struct Pricing: Decodable {
    let input: String?
    let output: String?
  }

  let data: [Model]
}
