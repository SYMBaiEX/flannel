//
//  AssistantMessageRunDetails.swift
//  flannel
//
//  Created by OpenAI Codex on 7/4/26.
//

import Foundation

nonisolated struct AssistantMessageRunDetailRow: Hashable, Sendable {
    var title: String
    var value: String
    var systemImage: String
}

nonisolated struct AssistantMessageContextUsageSummary: Hashable, Sendable {
    var usedTokens: Int
    var windowTokens: Int?

    var fraction: Double? {
        guard let windowTokens, windowTokens > 0 else { return nil }
        return min(1, max(0, Double(usedTokens) / Double(windowTokens)))
    }

    var percentText: String? {
        guard let fraction else { return nil }
        return "\(Int((fraction * 100).rounded()))%"
    }

    var displayText: String {
        if let windowTokens, let percentText {
            return "\(Self.formatTokens(usedTokens)) of \(Self.formatTokens(windowTokens)) tokens (\(percentText))"
        }
        return "\(Self.formatTokens(usedTokens)) tokens"
    }

    var accessibilityLabel: String {
        if let windowTokens, let percentText {
            return "Context usage, \(Self.formatTokens(usedTokens)) of \(Self.formatTokens(windowTokens)) tokens, \(percentText)"
        }
        return "Context usage, \(Self.formatTokens(usedTokens)) tokens"
    }

    var isNearLimit: Bool {
        guard let fraction else { return false }
        return fraction >= 0.85
    }

    private static func formatTokens(_ count: Int) -> String {
        count.formatted(.number.grouping(.automatic))
    }
}

extension AssistantMessage {
    var contextUsageSummary: AssistantMessageContextUsageSummary? {
        guard let contextTokenCount else { return nil }
        return AssistantMessageContextUsageSummary(
            usedTokens: contextTokenCount,
            windowTokens: contextWindowTokens
        )
    }

    var runDetailRows: [AssistantMessageRunDetailRow] {
        var rows: [AssistantMessageRunDetailRow] = []

        if let runStatus {
            rows.append(AssistantMessageRunDetailRow(
                title: "Status",
                value: runStatus.title,
                systemImage: runStatus.runDetailIcon
            ))
        }

        if let providerDisplayName = Self.trimmedNonEmpty(providerDisplayName) {
            let model = Self.trimmedNonEmpty(modelIdentifier)
            rows.append(AssistantMessageRunDetailRow(
                title: "Route",
                value: [providerDisplayName, model].compactMap { $0 }.joined(separator: " - "),
                systemImage: "cpu"
            ))
        } else if let model = Self.trimmedNonEmpty(modelIdentifier) {
            rows.append(AssistantMessageRunDetailRow(
                title: "Model",
                value: model,
                systemImage: "memorychip"
            ))
        }

        if providerAccessMode != nil || providerPrivacyScope != nil {
            rows.append(AssistantMessageRunDetailRow(
                title: "Boundary",
                value: [
                    providerAccessMode?.title,
                    providerPrivacyScope?.title
                ].compactMap { $0 }.joined(separator: " - "),
                systemImage: providerPrivacyScope?.runDetailIcon ?? providerAccessMode?.runDetailIcon ?? "lock"
            ))
        }

        if let tokenText = runTokenText {
            rows.append(AssistantMessageRunDetailRow(
                title: "Tokens",
                value: tokenText,
                systemImage: "text.word.spacing"
            ))
        }

        if let contextUsageSummary {
            rows.append(AssistantMessageRunDetailRow(
                title: "Context",
                value: contextUsageSummary.displayText,
                systemImage: "gauge.with.dots.needle.33percent"
            ))
        }

        if let latencyText = runLatencyText {
            rows.append(AssistantMessageRunDetailRow(
                title: "Latency",
                value: latencyText,
                systemImage: "timer"
            ))
        }

        if let estimatedCostMicros, estimatedCostMicros > 0 {
            rows.append(AssistantMessageRunDetailRow(
                title: "Cost",
                value: estimatedCostMicros.formattedRunCost,
                systemImage: "dollarsign.circle"
            ))
        }

        if let fallbackReason = Self.trimmedNonEmpty(fallbackReason) {
            rows.append(AssistantMessageRunDetailRow(
                title: "Fallback",
                value: fallbackReason,
                systemImage: "exclamationmark.circle"
            ))
        }

        return rows
    }

    var hasRunDetailDisclosure: Bool {
        !runDetailRows.isEmpty
    }

    private var runTokenText: String? {
        let suffix = tokenCountsAreEstimated ? " estimated" : ""
        if let inputTokenCount, let outputTokenCount {
            return "\(Self.formatTokens(inputTokenCount)) input / \(Self.formatTokens(outputTokenCount)) output\(suffix)"
        }
        if let inputTokenCount {
            return "\(Self.formatTokens(inputTokenCount)) input\(suffix)"
        }
        if let outputTokenCount {
            return "\(Self.formatTokens(outputTokenCount)) output\(suffix)"
        }
        return nil
    }

    private var runLatencyText: String? {
        let total = latencyMilliseconds.map { "\($0.formattedRunLatency) total" }
        let first = firstTokenLatencyMilliseconds.map { "\($0.formattedRunLatency) first token" }
        let parts = [total, first].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " - ")
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func formatTokens(_ count: Int) -> String {
        count.formatted(.number.grouping(.automatic))
    }
}

private extension Int {
    var formattedRunLatency: String {
        if self < 1_000 {
            return "\(self) ms"
        }
        let seconds = Double(self) / 1_000
        return "\(seconds.formatted(.number.precision(.fractionLength(1)))) s"
    }

    var formattedRunCost: String {
        let dollars = Double(self) / 1_000_000
        return dollars.formatted(.currency(code: "USD").precision(.fractionLength(4)))
    }
}

private extension AssistantMessageRunStatus {
    var runDetailIcon: String {
        switch self {
        case .queued:
            "clock"
        case .streaming:
            "waveform"
        case .completed:
            "checkmark.circle"
        case .fallback:
            "arrow.triangle.2.circlepath"
        case .failed:
            "exclamationmark.triangle"
        case .stopped:
            "stop.circle"
        }
    }
}

private extension ProviderAccessMode {
    var runDetailIcon: String {
        switch self {
        case .localServer:
            "desktopcomputer"
        case .apiKey:
            "key"
        case .subscriptionCLI:
            "terminal"
        case .openAICompatible:
            "arrow.left.arrow.right"
        case .anthropicCompatible:
            "text.bubble"
        case .aiSDKBridge:
            "shippingbox"
        }
    }
}

private extension ProviderPrivacyScope {
    var runDetailIcon: String {
        switch self {
        case .localOnly:
            "lock"
        case .externalAPI:
            "network"
        case .localCLI:
            "terminal"
        case .bridgeService:
            "point.3.connected.trianglepath.dotted"
        }
    }
}
