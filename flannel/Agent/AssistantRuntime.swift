//
//  AssistantRuntime.swift
//  flannel
//
//  Created by OpenAI Codex on 6/28/26.
//

import Foundation

struct AssistantRuntime: Sendable {
    nonisolated init() {}

    func run(_ request: AssistantRuntimeRequest) throws -> AssistantRunResult {
        let trimmedPrompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            throw AssistantRuntimeError.emptyPrompt
        }

        let contextPacket = buildContextPacket(
            context: request.context,
            selectedChips: request.selectedChips
        )
        let providerResolution = resolveProvider(request.provider)
        let toolPlans = routeTools(
            prompt: trimmedPrompt,
            context: request.context
        )
        let executedTools = toolPlans.map {
            execute(
                $0,
                context: request.context,
                contextPacket: contextPacket,
                providerStatus: providerResolution.status
            )
        }

        return AssistantRunResult(
            responseText: composeResponse(
                prompt: trimmedPrompt,
                contextPacket: contextPacket,
                providerStatus: providerResolution.status,
                executedTools: executedTools
            ),
            toolActivity: buildActivity(
                contextPacket: contextPacket,
                providerResolution: providerResolution,
                toolPlans: toolPlans,
                executedTools: executedTools
            ),
            usedFallback: providerResolution.status.availability == .unavailable,
            providerBadge: providerResolution.status.badge,
            note: providerResolution.status.detail,
            providerStatus: providerResolution.status,
            executedTools: executedTools
        )
    }

    private func buildContextPacket(
        context: AssistantContextSnapshot,
        selectedChips: [AssistantContextChip]
    ) -> ContextPacket {
        guard !selectedChips.isEmpty else {
            return ContextPacket(
                summary: "No explicit context chips were selected. The runtime used the ambient workspace snapshot.",
                traceDetail: "No chips selected. Using the ambient workspace snapshot."
            )
        }

        let lines = selectedChips.map { "\($0.title): \($0.detail)" }
        return ContextPacket(
            summary: "Selected context chips: \(lines.joined(separator: "; "))",
            traceDetail: "Loaded \(selectedChips.count) selected context chip(s) into the local runtime packet."
        )
    }

    private func resolveProvider(_ provider: ProviderConfiguration?) -> ProviderResolution {
        guard let provider else {
            return ProviderResolution(
                status: AssistantProviderStatus(
                    availability: .localOnly,
                    badge: "Local Only",
                    detail: "No provider is selected. The assistant ran only local deterministic tools.",
                    requestWasSent: false
                ),
                trace: AssistantTraceStep(
                    id: "resolve-provider",
                    title: "Resolve provider",
                    detail: "No provider selected. No external request path exists for this run.",
                    state: .completed
                )
            )
        }

        let endpoint = provider.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = provider.modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)

        let secret = (provider.secretReference ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let missingRequirement: String? = switch provider.accessMode {
        case .localServer, .openAICompatible, .anthropicCompatible, .aiSDKBridge:
            endpoint.isEmpty || model.isEmpty ? "endpoint or model" : nil
        case .apiKey:
            endpoint.isEmpty || model.isEmpty || secret.isEmpty ? "endpoint, model, or Keychain reference" : nil
        case .subscriptionCLI:
            endpoint.isEmpty || model.isEmpty ? "CLI command or model label" : nil
        }

        if let missingRequirement {
            return ProviderResolution(
                status: AssistantProviderStatus(
                    availability: .unavailable,
                    badge: "\(provider.displayName) Unavailable",
                    detail: "\(provider.displayName) is selected in \(provider.accessMode.title) mode, but \(missingRequirement) is missing. No request was sent.",
                    requestWasSent: false
                ),
                trace: AssistantTraceStep(
                    id: "resolve-provider",
                    title: "Resolve provider",
                    detail: "\(provider.displayName) needs \(missingRequirement) before a live transport can exist.",
                    state: .failed
                )
            )
        }

        return ProviderResolution(
            status: AssistantProviderStatus(
                availability: .configured,
                badge: "\(provider.displayName) Configured",
                detail: "\(provider.displayName) is configured in \(provider.accessMode.title) mode with \(model), but this runtime is still deterministic and did not send a request.",
                requestWasSent: false
            ),
            trace: AssistantTraceStep(
                id: "resolve-provider",
                title: "Resolve provider",
                detail: "Detected a complete \(provider.displayName) configuration. Live streaming transport is planned but not used by this local deterministic runtime.",
                state: .completed
            )
        )
    }

    private func routeTools(
        prompt: String,
        context: AssistantContextSnapshot
    ) -> [LocalToolPlan] {
        let lowered = prompt.lowercased()

        if matchesAny(lowered, terms: ["contract", "schema", "tool"]) {
            return [LocalToolPlan(id: "tool-contract", title: "Define local tool contract", kind: .toolContract)]
        }

        if matchesAny(lowered, terms: ["ollama", "openai", "provider", "model", "endpoint", "key"]) {
            return [LocalToolPlan(id: "provider-readiness", title: "Inspect provider readiness", kind: .providerReadiness)]
        }

        if matchesAny(lowered, terms: ["draft", "script", "rewrite", "review", "revise"]),
           context.draft != nil {
            return [LocalToolPlan(id: "draft-review", title: "Review current draft", kind: .draftReview)]
        }

        if matchesAny(lowered, terms: ["asset", "source", "video", "thread", "link", "summarize"]),
           context.libraryAsset != nil {
            return [LocalToolPlan(id: "source-brief", title: "Summarize selected source", kind: .sourceBrief)]
        }

        if matchesAny(lowered, terms: ["workspace", "prioritize", "next", "plan"]) {
            return [LocalToolPlan(id: "workspace-summary", title: "Summarize workspace state", kind: .workspaceSummary)]
        }

        return [LocalToolPlan(id: "next-action", title: "Recommend next local action", kind: .nextAction)]
    }

    private func execute(
        _ plan: LocalToolPlan,
        context: AssistantContextSnapshot,
        contextPacket: ContextPacket,
        providerStatus: AssistantProviderStatus
    ) -> AssistantToolResult {
        switch plan.kind {
        case .workspaceSummary:
            return AssistantToolResult(
                id: plan.id,
                title: plan.title,
                output: workspaceSummary(
                    context: context,
                    contextPacket: contextPacket,
                    providerStatus: providerStatus
                )
            )

        case .providerReadiness:
            return AssistantToolResult(
                id: plan.id,
                title: plan.title,
                output: providerReadiness(providerStatus)
            )

        case .draftReview:
            return AssistantToolResult(
                id: plan.id,
                title: plan.title,
                output: draftReview(context: context)
            )

        case .sourceBrief:
            return AssistantToolResult(
                id: plan.id,
                title: plan.title,
                output: sourceBrief(context: context)
            )

        case .toolContract:
            return AssistantToolResult(
                id: plan.id,
                title: plan.title,
                output: toolContract(context: context)
            )

        case .nextAction:
            return AssistantToolResult(
                id: plan.id,
                title: plan.title,
                output: nextAction(
                    context: context,
                    providerStatus: providerStatus
                )
            )
        }
    }

    private func workspaceSummary(
        context: AssistantContextSnapshot,
        contextPacket: ContextPacket,
        providerStatus: AssistantProviderStatus
    ) -> String {
        var lines = [
            "Destination: \(context.destination.title).",
            "Provider state: \(providerStatus.badge)."
        ]

        if let project = context.project {
            lines.append("Active project: \(project.title). \(project.summary)")
        } else {
            lines.append("Active project: none selected.")
        }

        if let draft = context.draft {
            lines.append("Draft: \(draft.title) [\(draft.status.rawValue)]. \(draft.summary)")
        } else {
            lines.append("Draft: none selected.")
        }

        if let asset = context.libraryAsset {
            lines.append("Source: \(asset.title) [\(asset.kind.rawValue)].")
        }

        lines.append("Context packet: \(contextPacket.summary)")
        return lines.joined(separator: "\n")
    }

    private func providerReadiness(_ providerStatus: AssistantProviderStatus) -> String {
        switch providerStatus.availability {
        case .localOnly:
            return """
            No provider is active. The assistant can still inspect local workspace context and run deterministic tools, but no model request path exists yet.
            """
        case .configured:
            return """
            \(providerStatus.detail)
            To enable live inference later, keep the runtime contract and replace only the transport boundary.
            """
        case .unavailable:
            return """
            \(providerStatus.detail)
            Fix the missing configuration first, then wire a transport without changing the local tool contract.
            """
        }
    }

    private func draftReview(context: AssistantContextSnapshot) -> String {
        guard let draft = context.draft else {
            return "No draft is selected, so there is nothing to review."
        }

        let projectTitle = context.project?.title ?? "the current workspace"
        return """
        Draft focus: \(draft.title) [\(draft.status.rawValue)].
        Existing summary: \(draft.summary.isEmpty ? "No draft summary is saved." : draft.summary)
        Suggested refinement: tighten the opening so it states one clear claim tied to \(projectTitle).
        Follow-up action: turn the strongest sentence into a publish-ready hook before expanding the body.
        """
    }

    private func sourceBrief(context: AssistantContextSnapshot) -> String {
        guard let asset = context.libraryAsset else {
            return "No source is selected, so the source summary tool has nothing to inspect."
        }

        let tagSummary = asset.tags.isEmpty ? "No tags are attached yet." : "Tags: \(asset.tags.joined(separator: ", "))."
        return """
        Source: \(asset.title) [\(asset.kind.rawValue)].
        Summary: \(asset.summary.isEmpty ? "No local summary is saved yet." : asset.summary)
        \(tagSummary)
        Best local next step: attach the source to a draft or project before asking for a synthesis.
        """
    }

    private func toolContract(context: AssistantContextSnapshot) -> String {
        let projectLine = context.project?.title ?? "workspace selection"
        return """
        Tool: local.workspace.inspect
        Inputs: prompt text, selected context chips, assistant context snapshot, optional provider configuration.
        Outputs: provider status, ordered trace steps, deterministic tool results, assistant-visible response text.
        Failure handling: reject empty prompts, mark provider setup as unavailable when configuration is incomplete, and keep response generation local when transport is absent.
        UI contract: show selected chips, show every trace step in order, and display that no external request was sent unless a transport explicitly records one.
        Current grounding target: \(projectLine).
        """
    }

    private func nextAction(
        context: AssistantContextSnapshot,
        providerStatus: AssistantProviderStatus
    ) -> String {
        if providerStatus.availability == .unavailable {
            return "Next action: fix the provider configuration before expecting live model output. Until then, use the local tools for grounded workspace inspection."
        }

        if context.draft != nil {
            return "Next action: review the selected draft and turn one concrete revision into a saved edit or publish checklist item."
        }

        if context.libraryAsset != nil {
            return "Next action: convert the selected source into a draft or summary so the workspace has a concrete artifact to iterate on."
        }

        if context.project != nil {
            return "Next action: define one narrow deliverable for the active project, then ask the assistant to inspect that draft or source context."
        }

        return "Next action: select a project, draft, or source so the assistant can ground the next local tool run in real workspace state."
    }

    private func composeResponse(
        prompt: String,
        contextPacket: ContextPacket,
        providerStatus: AssistantProviderStatus,
        executedTools: [AssistantToolResult]
    ) -> String {
        let toolSection = executedTools.map { tool in
            "[\((tool.title))]\n\(tool.output)"
        }
        .joined(separator: "\n\n")

        return """
        Local assistant runtime completed. No external model request was sent.

        Prompt focus: \(prompt)
        Provider status: \(providerStatus.badge)
        Provider detail: \(providerStatus.detail)
        Context: \(contextPacket.summary)

        \(toolSection)
        """
    }

    private func buildActivity(
        contextPacket: ContextPacket,
        providerResolution: ProviderResolution,
        toolPlans: [LocalToolPlan],
        executedTools: [AssistantToolResult]
    ) -> [AssistantTraceStep] {
        var steps = [
            AssistantTraceStep(
                id: "collect-context",
                title: "Collect context",
                detail: contextPacket.traceDetail,
                state: .completed
            ),
            providerResolution.trace,
            AssistantTraceStep(
                id: "route-local-tools",
                title: "Route local tools",
                detail: "Mapped the prompt to \(toolPlans.map(\.title).joined(separator: ", ")).",
                state: .completed
            )
        ]

        steps.append(
            contentsOf: executedTools.map { tool in
                AssistantTraceStep(
                    id: "tool-\(tool.id)",
                    title: tool.title,
                    detail: "Executed locally with deterministic workspace data.",
                    state: .completed
                )
            }
        )

        steps.append(
            AssistantTraceStep(
                id: "assemble-response",
                title: "Assemble response",
                detail: "Returned \(executedTools.count) local tool result(s) with an explicit no-request transport status.",
                state: .completed
            )
        )

        return steps
    }

    private func matchesAny(_ source: String, terms: [String]) -> Bool {
        terms.contains(where: source.contains)
    }

    private struct ContextPacket {
        var summary: String
        var traceDetail: String
    }

    private struct ProviderResolution {
        var status: AssistantProviderStatus
        var trace: AssistantTraceStep
    }

    private struct LocalToolPlan {
        var id: String
        var title: String
        var kind: LocalToolKind
    }

    private enum LocalToolKind {
        case workspaceSummary
        case providerReadiness
        case draftReview
        case sourceBrief
        case toolContract
        case nextAction
    }
}

enum AssistantRuntimeError: LocalizedError {
    case emptyPrompt

    var errorDescription: String? {
        switch self {
        case .emptyPrompt:
            return "Enter a prompt before sending a request."
        }
    }
}
