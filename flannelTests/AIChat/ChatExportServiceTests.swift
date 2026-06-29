//
//  ChatExportServiceTests.swift
//  flannelTests
//

import Foundation
import Testing
@testable import flannel

struct ChatExportServiceTests {
    @Test("Markdown export includes thread metadata, messages, provider data, and citations")
    func markdownExportIncludesChatContext() throws {
        let service = ChatExportService()
        let thread = sampleThread()

        let markdown = service.markdown(thread: thread, exportedAt: exportDate)

        #expect(markdown.contains("# Research <Thread>"))
        #expect(markdown.contains("- Thread ID: `\(thread.id.uuidString)`"))
        #expect(markdown.contains("<!-- flannel-message-start"))
        #expect(markdown.contains("<!-- flannel-message-text-start"))
        #expect(markdown.contains("<!-- flannel-message-end"))
        #expect(markdown.contains("## User - 2026-06-28T10:02:00.000Z"))
        #expect(markdown.contains("Status: Completed"))
        #expect(markdown.contains("Provider: Local Ollama"))
        #expect(markdown.contains("Provider mode: Local Server"))
        #expect(markdown.contains("Privacy scope: Local Only"))
        #expect(markdown.contains("Model: llama3.1"))
        #expect(markdown.contains("Context tokens: 96 / 16000"))
        #expect(markdown.contains("First token latency: 140 ms"))
        #expect(markdown.contains("Token counts: estimated"))
        #expect(markdown.contains("### Requested Tool Calls"))
        #expect(markdown.contains("workspace_search"))
        #expect(markdown.contains("Provider call ID: `call_workspace`"))
        #expect(markdown.contains("### Attachments"))
        #expect(markdown.contains("brief.md"))
        #expect(markdown.contains("Attachment excerpt"))
        #expect(markdown.contains("### Sources"))
        #expect(markdown.contains("Local notes: Private context"))
    }

    @Test("JSON export is pretty printed and preserves the Codable thread payload")
    func jsonExportPreservesThreadPayload() throws {
        let data = try ChatExportService().export(
            thread: sampleThread(),
            format: .json,
            exportedAt: exportDate
        )

        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let thread = try #require(object["thread"] as? [String: Any])
        let messages = try #require(thread["messages"] as? [[String: Any]])

        #expect(object["schemaVersion"] as? Int == 1)
        #expect(thread["title"] as? String == "Research <Thread>")
        #expect(messages.count == 3)
        let userAttachments = try #require(messages[1]["attachments"] as? [[String: Any]])
        #expect(userAttachments.first?["title"] as? String == "brief.md")
        #expect(messages.last?["providerDisplayName"] as? String == "Local Ollama")
        #expect(messages.last?["runStatus"] as? String == "completed")
        #expect(messages.last?["providerAccessMode"] as? String == "localServer")
        #expect(messages.last?["providerPrivacyScope"] as? String == "localOnly")
        #expect(messages.last?["contextTokenCount"] as? Int == 96)
        #expect(messages.last?["contextWindowTokens"] as? Int == 16_000)
        #expect(messages.last?["firstTokenLatencyMilliseconds"] as? Int == 140)
        #expect(messages.last?["tokenCountsAreEstimated"] as? Bool == true)
        let toolCalls = try #require(messages.last?["toolCalls"] as? [[String: Any]])
        #expect(toolCalls.first?["toolName"] as? String == "workspace_search")
        #expect(toolCalls.first?["providerCallID"] as? String == "call_workspace")
    }

    @Test("HTML export escapes user content and keeps message structure")
    func htmlExportEscapesUserContent() {
        let html = ChatExportService().html(thread: sampleThread(), exportedAt: exportDate)

        #expect(html.contains("<!doctype html>"))
        #expect(html.contains("Research &lt;Thread&gt;"))
        #expect(html.contains("Explain &lt;script&gt; tags &amp; safety."))
        #expect(html.contains("<section class=\"attachments\">"))
        #expect(html.contains("<section class=\"tool-calls\">"))
        #expect(html.contains("workspace_search"))
        #expect(html.contains("Attachment excerpt &amp; details."))
        #expect(html.contains("class=\"message assistant\""))
        #expect(html.contains("Status: Completed"))
        #expect(html.contains("Provider mode: Local Server"))
        #expect(html.contains("Context tokens: 96 / 16000"))
        #expect(html.contains("First token latency: 140 ms"))
        #expect(html.contains("<section class=\"sources\">"))
    }

    @Test("Legacy assistant messages decode without run telemetry")
    @MainActor
    func legacyAssistantMessageDecodesWithoutTelemetry() throws {
        let data = Data(
            """
            {
              "id": "3D8CCCB1-CE41-4EEA-88C5-BB5B89F9B7BA",
              "role": "assistant",
              "text": "Legacy response",
              "createdAt": 1782640980
            }
            """.utf8
        )

        let message = try JSONDecoder().decode(AssistantMessage.self, from: data)

        #expect(message.text == "Legacy response")
        #expect(message.runStatus == nil)
        #expect(message.providerAccessMode == nil)
        #expect(message.providerPrivacyScope == nil)
        #expect(message.contextTokenCount == nil)
        #expect(message.tokenCountsAreEstimated == false)
        #expect(message.toolCalls.isEmpty)
    }

    @Test("PDF export produces a non-empty PDF document")
    func pdfExportProducesPDFData() throws {
        let data = try ChatExportService().export(
            thread: sampleThread(),
            format: .pdf,
            exportedAt: exportDate
        )

        #expect(data.count > 100)
        #expect(String(data: data.prefix(4), encoding: .utf8) == "%PDF")
    }

    @Test("Default export filename is slugged and format-specific")
    func defaultFilenameUsesSlugAndExtension() {
        let filename = ChatExportService().defaultFilename(
            for: sampleThread(),
            format: .markdown
        )

        #expect(filename == "research-thread.md")
    }

    private var exportDate: Date {
        Date(timeIntervalSince1970: 1_782_640_800)
    }

    private func sampleThread() -> AssistantThread {
        let threadID = UUID(uuidString: "5C1D5556-7BB7-4B23-BC8B-42D36EBE1A5F")!
        let createdAt = Date(timeIntervalSince1970: 1_782_640_740)
        let userDate = Date(timeIntervalSince1970: 1_782_640_920)
        let assistantDate = Date(timeIntervalSince1970: 1_782_640_980)
        let runStartedAt = Date(timeIntervalSince1970: 1_782_640_970)
        let runCompletedAt = Date(timeIntervalSince1970: 1_782_640_980)

        return AssistantThread(
            id: threadID,
            title: "Research <Thread>",
            mode: .research,
            messages: [
                AssistantMessage(
                    role: .system,
                    text: "Stay local first.",
                    createdAt: createdAt
                ),
                AssistantMessage(
                    role: .user,
                    text: "Explain <script> tags & safety.",
                    attachments: [
                        AIChatAttachment(
                            kind: .textSnippet,
                            title: "brief.md",
                            mimeType: "text/markdown",
                            localPath: "/tmp/brief.md",
                            byteCount: 128,
                            excerpt: "Attachment excerpt & details."
                        )
                    ],
                    createdAt: userDate
                ),
                AssistantMessage(
                    role: .assistant,
                    text: "They are executable HTML elements. Escape untrusted content.",
                    createdAt: assistantDate,
                    citations: [
                        AIChatCitation(
                            title: "Local notes",
                            snippet: "Private context"
                        )
                    ],
                    providerDisplayName: "Local Ollama",
                    modelIdentifier: "llama3.1",
                    inputTokenCount: 20,
                    outputTokenCount: 40,
                    latencyMilliseconds: 550,
                    firstTokenLatencyMilliseconds: 140,
                    estimatedCostMicros: 0,
                    providerAccessMode: .localServer,
                    providerPrivacyScope: .localOnly,
                    runStatus: .completed,
                    startedAt: runStartedAt,
                    completedAt: runCompletedAt,
                    contextTokenCount: 96,
                    contextWindowTokens: 16_000,
                    tokenCountsAreEstimated: true,
                    toolCalls: [
                        AIToolCallRecord(
                            providerCallID: "call_workspace",
                            toolName: "workspace_search",
                            permissionScope: .queryRAGIndex,
                            argumentsJSON: #"{"query":"local notes"}"#,
                            wasApproved: false,
                            startedAt: runStartedAt
                        )
                    ]
                )
            ],
            tagNames: ["security", "html"],
            createdAt: createdAt,
            updatedAt: assistantDate
        )
    }
}
