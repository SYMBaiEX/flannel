//
//  ProviderCostEstimator.swift
//  flannel
//
//  Created by OpenAI Codex on 6/29/26.
//

import Foundation

nonisolated struct ProviderCostEstimator: Sendable {
    static let shared = ProviderCostEstimator()

    nonisolated init() {}

    nonisolated func estimatedCostMicros(
        provider: ProviderConfiguration?,
        inputTokens: Int,
        outputTokens: Int
    ) -> Int? {
        guard let provider,
              let pricing = pricing(for: provider) else {
            return nil
        }

        let inputCostDollars = (Double(max(0, inputTokens)) / 1_000_000.0) * pricing.inputCostPerMillionTokens
        let outputCostDollars = (Double(max(0, outputTokens)) / 1_000_000.0) * pricing.outputCostPerMillionTokens
        return Int(((inputCostDollars + outputCostDollars) * 1_000_000.0).rounded())
    }

    nonisolated func marginalCostPerMillionTokens(_ provider: ProviderConfiguration) -> Double {
        switch provider.privacyScope {
        case .localOnly, .localCLI:
            return 0
        case .bridgeService:
            guard let pricing = pricing(for: provider) else {
                return 0
            }
            return pricing.inputCostPerMillionTokens + pricing.outputCostPerMillionTokens
        case .externalAPI:
            guard let pricing = pricing(for: provider) else {
                return Double.greatestFiniteMagnitude
            }
            return pricing.inputCostPerMillionTokens + pricing.outputCostPerMillionTokens
        }
    }

    private nonisolated func pricing(for provider: ProviderConfiguration) -> ProviderTokenPricing? {
        guard let inputCost = provider.inputCostPerMillionTokens,
              let outputCost = provider.outputCostPerMillionTokens else {
            return nil
        }

        return ProviderTokenPricing(
            inputCostPerMillionTokens: max(0, inputCost),
            outputCostPerMillionTokens: max(0, outputCost)
        )
    }
}

private nonisolated struct ProviderTokenPricing: Hashable, Sendable {
    var inputCostPerMillionTokens: Double
    var outputCostPerMillionTokens: Double
}
