//
//  AssistantRuntimeTests.swift
//  flannelTests
//
//  Created by OpenAI Codex on 6/28/26.
//

import Foundation
import Testing
@testable import flannel

struct AssistantRuntimeTests {
    @Test func configuredOllamaStaysLocalAndGrounded() throws {
        let runtime = AssistantRuntime()
        let provider = ProviderConfiguration(
            kind: .ollama,
            displayName: "Local Ollama",
            endpoint: "http://localhost:11434",
            modelIdentifier: "llama3.1"
        )

        let result = try runtime.run(
            AssistantRuntimeRequest(
                prompt: "Summarize the workspace",
                context: makeContext(provider: provider),
                selectedChips: [
                    AssistantContextChip(
                        id: "project",
                        title: "Project",
                        detail: "Creator OS Launch",
                        symbolName: "folder",
                        isSelected: true
                    )
                ],
                provider: provider
            )
        )

        #expect(result.usedFallback == false)
        #expect(result.providerBadge == "Local Ollama Configured")
        #expect(result.providerStatus.requestWasSent == false)
        #expect(result.responseText.contains("No external model request was sent"))
        #expect(result.responseText.contains("Selected context chips: Project: Creator OS Launch"))
        #expect(result.toolActivity.contains { $0.id == "tool-workspace-summary" })
    }

    @Test func openAIWithoutKeyIsExplicitlyUnavailable() throws {
        let runtime = AssistantRuntime()
        let provider = ProviderConfiguration(
            kind: .openAI,
            displayName: "OpenAI",
            endpoint: "https://api.openai.com/v1",
            modelIdentifier: "gpt-4.1"
        )

        let result = try runtime.run(
            AssistantRuntimeRequest(
                prompt: "Review the current draft",
                context: makeContext(provider: provider),
                selectedChips: [],
                provider: provider
            )
        )

        #expect(result.usedFallback)
        #expect(result.providerBadge == "OpenAI Unavailable")
        #expect(result.note.contains("No request was sent"))
        #expect(result.toolActivity.contains {
            $0.id == "resolve-provider" && $0.state == .failed
        })
    }

    @Test func openAIWithStoredKeyRemainsConfiguredButLocal() throws {
        let runtime = AssistantRuntime()
        let provider = ProviderConfiguration(
            kind: .openAI,
            displayName: "OpenAI",
            endpoint: "https://api.openai.com/v1",
            modelIdentifier: "gpt-4.1",
            secretReference: "keychain:flannel/openai"
        )

        let result = try runtime.run(
            AssistantRuntimeRequest(
                prompt: "Review the current draft",
                context: makeContext(provider: provider),
                selectedChips: [],
                provider: provider
            )
        )

        #expect(result.usedFallback == false)
        #expect(result.providerBadge == "OpenAI Configured")
        #expect(result.note.contains("did not send a request"))
        #expect(result.providerStatus.requestWasSent == false)
        #expect(result.toolActivity.contains {
            $0.id == "resolve-provider" && $0.state == .completed
        })
    }

    @Test func ollamaWithoutEndpointIsExplicitlyUnavailable() throws {
        let runtime = AssistantRuntime()
        let provider = ProviderConfiguration(
            kind: .ollama,
            displayName: "Local Ollama",
            endpoint: "   ",
            modelIdentifier: "llama3.1"
        )

        let result = try runtime.run(
            AssistantRuntimeRequest(
                prompt: "Summarize the workspace",
                context: makeContext(provider: provider),
                selectedChips: [],
                provider: provider
            )
        )

        #expect(result.usedFallback)
        #expect(result.providerBadge == "Local Ollama Unavailable")
        #expect(result.note.contains("No request was sent"))
        #expect(result.toolActivity.contains {
            $0.id == "resolve-provider" && $0.state == .failed
        })
    }

    @Test func toolContractPromptRoutesToDeterministicLocalTool() throws {
        let runtime = AssistantRuntime()
        let provider = ProviderConfiguration(
            kind: .openAI,
            displayName: "OpenAI",
            endpoint: "https://api.openai.com/v1",
            modelIdentifier: "gpt-4.1",
            secretReference: "keychain:flannel/openai"
        )

        let result = try runtime.run(
            AssistantRuntimeRequest(
                prompt: "Draft a tool contract for the assistant",
                context: makeContext(provider: provider),
                selectedChips: [],
                provider: provider
            )
        )

        #expect(result.usedFallback == false)
        #expect(result.executedTools.first?.id == "tool-contract")
        #expect(result.executedTools.first?.output.contains("Tool: local.workspace.inspect") == true)
        #expect(result.toolActivity.first?.detail.contains("ambient workspace snapshot") == true)
    }

    private func makeContext(provider: ProviderConfiguration?) -> AssistantContextSnapshot {
        let project = WorkspaceProject(
            title: "Creator OS Launch",
            summary: "Define the first local-first workflow for research, drafts, and publishing."
        )
        let draft = DraftDocument(
            title: "Why local-first creator tooling matters",
            platform: .youtube,
            status: .inProgress,
            summary: "Opening script for the product announcement."
        )
        let thread = AssistantThread(title: "Workspace Copilot")

        return AssistantContextSnapshot(
            destination: .youtube,
            provider: provider,
            project: project,
            draft: draft,
            libraryAsset: nil,
            calendarEntry: nil,
            thread: thread,
            dashboard: WorkspaceDashboardSnapshot(
                sourceCount: 4,
                draftCount: 2,
                projectCount: 1,
                automationCount: 2,
                pendingTranscriptCount: 1,
                pendingSummaryCount: 1,
                scheduledDraftCount: 1,
                confirmationCount: 1
            ),
            integrationRows: [
                IntegrationStatusRow(
                    id: "youtube",
                    title: "YouTube",
                    detail: "Connected account with transcript queue",
                    status: .ready
                )
            ],
            pendingConfirmationCount: 1
        )
    }
}
