//
//  ChatProviderFallbackPolicyTests.swift
//  flannelTests
//

import Testing
@testable import flannel

struct ChatProviderFallbackPolicyTests {
    @Test("Partial text stream failures retry the next provider")
    func partialTextStreamFailureRetriesNextProvider() {
        let decision = ChatProviderFallbackPolicy.decisionAfterStreamFailure(
            providerName: "ChatGPT/Codex CLI",
            nextProviderName: "Local Ollama",
            errorDescription: "connection reset",
            emittedText: true,
            emittedToolCalls: false,
            isCancellation: false
        )

        guard case .retryNextProvider(let reason, let retryNotice) = decision else {
            Issue.record("Expected retry decision")
            return
        }

        #expect(reason == "Stream interrupted after partial output (text): connection reset")
        #expect(retryNotice == "ChatGPT/Codex CLI interrupted after streaming partial text. Retrying with Local Ollama.\n\nStream interrupted after partial output (text): connection reset")
    }

    @Test("Partial tool call stream failures retry without executing failed attempt")
    func partialToolCallStreamFailureRetriesNextProvider() {
        let decision = ChatProviderFallbackPolicy.decisionAfterStreamFailure(
            providerName: "Claude Code CLI",
            nextProviderName: "Anthropic API",
            errorDescription: "rate limit exceeded",
            emittedText: false,
            emittedToolCalls: true,
            isCancellation: false
        )

        guard case .retryNextProvider(let reason, let retryNotice) = decision else {
            Issue.record("Expected retry decision")
            return
        }

        #expect(reason == "Stream interrupted after partial output (tool calls): rate limit exceeded")
        #expect(retryNotice == "Claude Code CLI interrupted after streaming partial tool calls. Retrying with Anthropic API.\n\nStream interrupted after partial output (tool calls): rate limit exceeded")
    }

    @Test("Pre-stream failures retry quietly with the raw provider reason")
    func preStreamFailureRetriesQuietly() {
        let decision = ChatProviderFallbackPolicy.decisionAfterStreamFailure(
            providerName: "OpenAI API",
            nextProviderName: "Local Ollama",
            errorDescription: "missing Keychain secret",
            emittedText: false,
            emittedToolCalls: false,
            isCancellation: false
        )

        #expect(decision == .retryNextProvider(reason: "missing Keychain secret", retryNotice: nil))
    }

    @Test("Last provider failures finish current attempt")
    func lastProviderFailureFinishesCurrentAttempt() {
        let decision = ChatProviderFallbackPolicy.decisionAfterStreamFailure(
            providerName: "Local Ollama",
            nextProviderName: nil,
            errorDescription: "server unavailable",
            emittedText: true,
            emittedToolCalls: false,
            isCancellation: false
        )

        #expect(decision == .finishCurrentAttempt)
    }

    @Test("Cancelled streams never fallback to another provider")
    func cancelledStreamsNeverFallback() {
        let decision = ChatProviderFallbackPolicy.decisionAfterStreamFailure(
            providerName: "Claude Code CLI",
            nextProviderName: "Local Ollama",
            errorDescription: "cancelled",
            emittedText: true,
            emittedToolCalls: true,
            isCancellation: true
        )

        #expect(decision == .cancel)
    }

    @Test("Blank provider errors produce a readable fallback reason")
    func blankProviderErrorsProduceReadableReason() {
        let decision = ChatProviderFallbackPolicy.decisionAfterStreamFailure(
            providerName: "OpenAI-compatible",
            nextProviderName: "Local Ollama",
            errorDescription: "   ",
            emittedText: false,
            emittedToolCalls: false,
            isCancellation: false
        )

        #expect(decision == .retryNextProvider(
            reason: "The provider stream ended with an unknown error.",
            retryNotice: nil
        ))
    }
}
