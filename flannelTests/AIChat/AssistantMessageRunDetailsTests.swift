//
//  AssistantMessageRunDetailsTests.swift
//  flannelTests
//

import Foundation
import Testing
@testable import flannel

struct AssistantMessageRunDetailsTests {
    @Test("Assistant message run details summarize route context tokens latency and cost")
    func runDetailsSummarizeRouteContextTokensLatencyAndCost() throws {
        let message = AssistantMessage(
            role: .assistant,
            text: "Done.",
            providerDisplayName: "OpenAI API",
            modelIdentifier: "gpt-5.5",
            inputTokenCount: 12_000,
            outputTokenCount: 3_400,
            latencyMilliseconds: 1_320,
            firstTokenLatencyMilliseconds: 240,
            estimatedCostMicros: 12_345,
            providerAccessMode: .apiKey,
            providerPrivacyScope: .externalAPI,
            runStatus: .completed,
            contextTokenCount: 16_384,
            contextWindowTokens: 32_768,
            tokenCountsAreEstimated: false
        )

        let context = try #require(message.contextUsageSummary)
        #expect(context.fraction == 0.5)
        #expect(context.percentText == "50%")
        #expect(context.displayText == "16,384 of 32,768 tokens (50%)")
        #expect(context.accessibilityLabel.contains("Context usage"))
        #expect(context.isNearLimit == false)

        let rows = message.runDetailRows
        #expect(rows.contains {
            $0.title == "Status" && $0.value == "Completed" && $0.systemImage == "checkmark.circle"
        })
        #expect(rows.contains {
            $0.title == "Route" && $0.value == "OpenAI API - gpt-5.5"
        })
        #expect(rows.contains {
            $0.title == "Boundary" && $0.value == "API Key - External API"
        })
        #expect(rows.contains {
            $0.title == "Tokens" && $0.value == "12,000 input / 3,400 output"
        })
        #expect(rows.contains {
            $0.title == "Context" && $0.value == "16,384 of 32,768 tokens (50%)"
        })
        #expect(rows.contains {
            $0.title == "Latency" && $0.value == "1.3 s total - 240 ms first token"
        })
        #expect(rows.contains {
            $0.title == "Cost" && $0.value.contains("$0.0123")
        })
        #expect(message.hasRunDetailDisclosure)
    }

    @Test("Assistant message run details mark estimates and near limit context")
    func runDetailsMarkEstimatedTokensAndNearLimitContext() throws {
        let message = AssistantMessage(
            role: .assistant,
            text: "Fallback response.",
            providerDisplayName: "Claude Code CLI",
            outputTokenCount: 512,
            latencyMilliseconds: 980,
            providerAccessMode: .subscriptionCLI,
            providerPrivacyScope: .localCLI,
            runStatus: .fallback,
            contextTokenCount: 91_000,
            contextWindowTokens: 100_000,
            tokenCountsAreEstimated: true,
            fallbackReason: "Primary provider timed out."
        )

        let context = try #require(message.contextUsageSummary)
        #expect(context.percentText == "91%")
        #expect(context.isNearLimit)

        let rows = message.runDetailRows
        #expect(rows.contains {
            $0.title == "Tokens" && $0.value == "512 output estimated"
        })
        #expect(rows.contains {
            $0.title == "Boundary" && $0.value == "Account CLI - Local CLI"
        })
        #expect(rows.contains {
            $0.title == "Fallback" && $0.value == "Primary provider timed out."
        })
    }
}
