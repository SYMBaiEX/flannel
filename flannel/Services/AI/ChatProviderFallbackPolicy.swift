//
//  ChatProviderFallbackPolicy.swift
//  flannel
//

import Foundation

nonisolated enum ChatProviderStreamFailureDecision: Equatable, Sendable {
    case cancel
    case retryNextProvider(reason: String, retryNotice: String?)
    case finishCurrentAttempt
}

nonisolated enum ChatProviderFallbackPolicy {
    static func decisionAfterStreamFailure(
        providerName: String,
        nextProviderName: String?,
        errorDescription: String,
        emittedText: Bool,
        emittedToolCalls: Bool,
        isCancellation: Bool
    ) -> ChatProviderStreamFailureDecision {
        if isCancellation {
            return .cancel
        }

        guard let nextProviderName else {
            return .finishCurrentAttempt
        }

        let reason = streamFailureReason(
            errorDescription: errorDescription,
            emittedText: emittedText,
            emittedToolCalls: emittedToolCalls
        )
        let retryNotice = partialStreamRetryNotice(
            providerName: providerName,
            nextProviderName: nextProviderName,
            reason: reason,
            emittedText: emittedText,
            emittedToolCalls: emittedToolCalls
        )

        return .retryNextProvider(reason: reason, retryNotice: retryNotice)
    }

    static func streamFailureReason(
        errorDescription: String,
        emittedText: Bool,
        emittedToolCalls: Bool
    ) -> String {
        let trimmedError = errorDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = trimmedError.isEmpty
            ? "The provider stream ended with an unknown error."
            : trimmedError

        guard emittedText || emittedToolCalls else {
            return detail
        }

        return "Stream interrupted after partial output (\(partialOutputDescription(emittedText: emittedText, emittedToolCalls: emittedToolCalls))): \(detail)"
    }

    static func partialStreamRetryNotice(
        providerName: String,
        nextProviderName: String,
        reason: String,
        emittedText: Bool,
        emittedToolCalls: Bool
    ) -> String? {
        guard emittedText || emittedToolCalls else {
            return nil
        }

        return "\(providerName) interrupted after streaming partial \(partialOutputDescription(emittedText: emittedText, emittedToolCalls: emittedToolCalls)). Retrying with \(nextProviderName).\n\n\(reason)"
    }

    private static func partialOutputDescription(emittedText: Bool, emittedToolCalls: Bool) -> String {
        switch (emittedText, emittedToolCalls) {
        case (true, true):
            "text and tool calls"
        case (true, false):
            "text"
        case (false, true):
            "tool calls"
        case (false, false):
            "no output"
        }
    }
}
