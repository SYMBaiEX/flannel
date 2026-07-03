//
//  ModelComparisonRecommendationTests.swift
//  flannelTests
//
//  Created by OpenAI Codex on 7/2/26.
//

import Foundation
import Testing
@testable import flannel

struct ModelComparisonRecommendationTests {
    @Test("Comparison recommendation uses observable route telemetry")
    func comparisonRecommendationUsesObservableRouteTelemetry() {
        let localProvider = ProviderConfiguration(
            id: UUID(uuidString: "3d1b0c38-b2a3-4d20-a4f9-8b3f6b624e4a")!,
            kind: .lmStudio,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "Local LM Studio",
            endpoint: "http://localhost:1234/v1",
            modelIdentifier: "local/recommended",
            isEnabled: true,
            connectionStatus: .ready,
            supportsStreaming: true
        )
        let externalProvider = ProviderConfiguration(
            id: UUID(uuidString: "a58cf354-03fc-45e2-88ee-7a841d827c40")!,
            kind: .openAI,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "Official OpenAI API",
            endpoint: "https://api.openai.com/v1",
            modelIdentifier: "gpt-4.1",
            isEnabled: true,
            connectionStatus: .ready,
            supportsStreaming: true
        )
        let failedProvider = ProviderConfiguration(
            id: UUID(uuidString: "f8e31e94-9989-4f5e-a8c9-fcbad96d9022")!,
            kind: .anthropic,
            accessMode: .apiKey,
            privacyScope: .externalAPI,
            displayName: "Anthropic API",
            endpoint: "https://api.anthropic.com",
            modelIdentifier: "claude-sonnet-4",
            isEnabled: true,
            connectionStatus: .ready,
            supportsStreaming: true
        )

        let localResult = ModelComparisonResult(
            provider: localProvider,
            status: .completed,
            text: "Local route answered with enough substance to compare observable behavior.",
            inputTokenCount: 128,
            outputTokenCount: 240,
            latencyMilliseconds: 620,
            firstTokenLatencyMilliseconds: 150,
            tokenCountsAreEstimated: false
        )
        let externalResult = ModelComparisonResult(
            provider: externalProvider,
            status: .completed,
            text: "External route answered too, but it was slower and left the machine.",
            inputTokenCount: 128,
            outputTokenCount: 240,
            latencyMilliseconds: 6_200,
            firstTokenLatencyMilliseconds: 2_400,
            estimatedCostMicros: 4_500,
            tokenCountsAreEstimated: false
        )
        let failedResult = ModelComparisonResult(
            provider: failedProvider,
            status: .failed,
            text: "Failed output should never win even if it has text.",
            errorMessage: "Provider failed."
        )
        let run = ModelComparisonRun(
            prompt: "Recommend the safest observable route.",
            providerIDs: [externalProvider.id, localProvider.id, failedProvider.id],
            results: [externalResult, localResult, failedResult]
        )

        #expect(run.recommendedResult?.providerID == localProvider.id)
        #expect(run.recommendationReasons(for: localResult).contains("local-only route"))
        #expect(run.recommendationReasons(for: localResult).contains("fast first token"))
        #expect(run.recommendationReasons(for: localResult).contains("measured tokens"))
        #expect(run.recommendationScore(for: failedResult) == Int.min)
    }

    @Test("Comparison recommendation requires completed nonempty output")
    func comparisonRecommendationRequiresCompletedNonemptyOutput() {
        let provider = ProviderConfiguration(
            id: UUID(uuidString: "5f40b10b-e6d7-4d76-8ee1-8e1d09b7ce02")!,
            kind: .ollama,
            accessMode: .localServer,
            privacyScope: .localOnly,
            displayName: "Queued Ollama",
            endpoint: "http://localhost:11434",
            modelIdentifier: "llama3.1",
            isEnabled: true,
            connectionStatus: .ready,
            supportsStreaming: true
        )
        let run = ModelComparisonRun(
            prompt: "Wait for finished output.",
            providerIDs: [provider.id],
            results: [
                ModelComparisonResult(provider: provider, status: .queued),
                ModelComparisonResult(provider: provider, status: .completed, text: "   ")
            ]
        )

        #expect(run.recommendedResult == nil)
    }
}
