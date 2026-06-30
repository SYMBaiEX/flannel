//
//  ProviderCostEstimatorTests.swift
//  flannelTests
//
//  Created by OpenAI Codex on 6/29/26.
//

import Foundation
import Testing
@testable import flannel

struct ProviderCostEstimatorTests {
    @Test("External API pricing produces transcript cost estimates and marginal routing cost")
    func externalAPIPricingProducesEstimates() {
        let provider = ProviderConfiguration(
            kind: .openAI,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "OpenAI API",
            endpoint: "https://api.openai.com/v1",
            modelIdentifier: "gpt-5.5",
            inputCostPerMillionTokens: 2.5,
            outputCostPerMillionTokens: 10
        )

        let estimate = ProviderCostEstimator.shared.estimatedCostMicros(
            provider: provider,
            inputTokens: 1_000_000,
            outputTokens: 500_000
        )

        #expect(estimate == 7_500_000)
        #expect(ProviderCostEstimator.shared.marginalCostPerMillionTokens(provider) == 12.5)
    }

    @Test("Local and account CLI routes are zero marginal cost but omit transcript cost chips")
    func localAndCLIRoutesAreFreeForRoutingWithoutTranscriptCost() {
        let local = ProviderConfiguration(
            kind: .ollama,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "Local Ollama",
            endpoint: "http://localhost:11434",
            modelIdentifier: "llama3.1"
        )
        let cli = ProviderConfiguration(
            kind: .chatGPTCLI,
            accessMode: .subscriptionCLI,
            privacyScope: .localCLI,
            displayName: "ChatGPT/Codex CLI",
            endpoint: "codex exec --json -",
            modelIdentifier: "chatgpt-subscription"
        )

        #expect(ProviderCostEstimator.shared.marginalCostPerMillionTokens(local) == 0)
        #expect(ProviderCostEstimator.shared.marginalCostPerMillionTokens(cli) == 0)
        #expect(ProviderCostEstimator.shared.estimatedCostMicros(provider: local, inputTokens: 100, outputTokens: 100) == nil)
        #expect(ProviderCostEstimator.shared.estimatedCostMicros(provider: cli, inputTokens: 100, outputTokens: 100) == nil)
    }

    @Test("Unknown external API pricing sorts after priced routes")
    func unknownExternalPricingSortsAfterPricedRoutes() {
        let unknown = ProviderConfiguration(
            kind: .customOpenAICompatible,
            accessMode: .openAICompatible,
            privacyScope: .externalAPI,
            displayName: "Unknown hosted route",
            endpoint: "https://example.com/v1",
            modelIdentifier: "hosted-model"
        )
        let priced = ProviderConfiguration(
            kind: .groq,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "Priced hosted route",
            endpoint: "https://api.groq.com/openai/v1",
            modelIdentifier: "llama-3.3-70b-versatile",
            inputCostPerMillionTokens: 0.2,
            outputCostPerMillionTokens: 0.6
        )

        #expect(ProviderCostEstimator.shared.marginalCostPerMillionTokens(unknown) == Double.greatestFiniteMagnitude)
        #expect(
            ProviderCostEstimator.shared.marginalCostPerMillionTokens(priced)
                < ProviderCostEstimator.shared.marginalCostPerMillionTokens(unknown)
        )
    }

    @Test("Bridge routes preserve free local bridge behavior when pricing is unknown")
    func bridgeRoutesPreserveFreeUnknownPricingBehavior() {
        let bridge = ProviderConfiguration(
            kind: .vercelAISDKBridge,
            accessMode: .aiSDKBridge,
            privacyScope: .bridgeService,
            displayName: "Local AI SDK Bridge",
            endpoint: "http://localhost:4177",
            modelIdentifier: "bridge-default-model"
        )

        #expect(ProviderCostEstimator.shared.marginalCostPerMillionTokens(bridge) == 0)
        #expect(ProviderCostEstimator.shared.estimatedCostMicros(provider: bridge, inputTokens: 1_000, outputTokens: 1_000) == nil)
    }
}
