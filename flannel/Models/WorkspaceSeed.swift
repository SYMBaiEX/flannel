//
//  WorkspaceSeed.swift
//  flannel
//
//  Created by Codex on 6/28/26.
//

import Foundation

enum WorkspaceSeed {
    static func starterWorkspace(now: Date = .now) -> Item {
        let calendar = Calendar.current

        let openAI = ProviderConfiguration(
            kind: .openAI,
            displayName: "OpenAI",
            endpoint: "https://api.openai.com/v1",
            modelIdentifier: "gpt-4.1",
            connectionStatus: .needsAttention,
            lastErrorMessage: "API key not configured locally.",
            isLocalPreferred: false,
            availableModels: ["gpt-4.1", "gpt-4.1-mini"],
            supportsStructuredOutput: true
        )

        let ollama = ProviderConfiguration(
            kind: .ollama,
            displayName: "Local Ollama",
            endpoint: "http://localhost:11434",
            modelIdentifier: "llama3.1",
            isEnabled: true,
            temperature: 0.2,
            lastValidatedAt: calendar.date(byAdding: .minute, value: -18, to: now),
            connectionStatus: .ready,
            isLocalPreferred: true,
            availableModels: ["llama3.1", "qwen2.5:14b", "mistral-nemo"],
            supportsStructuredOutput: false
        )

        let youtubeAccount = CreatorAccount(
            platform: .youtube,
            handle: "@symbiex",
            displayName: "SYMBiEX",
            profileURL: URL(string: "https://youtube.com/@symbiex"),
            followerCount: 1420,
            lastSyncedAt: calendar.date(byAdding: .hour, value: -4, to: now),
            platformAccountID: "UC-SYMBIEX",
            connectionStatus: .ready,
            syncStatus: .succeeded,
            pendingImportCount: 1,
            readAccessGranted: true,
            publishAccessGranted: false,
            tags: ["youtube", "video", "launch"]
        )

        let xAccount = CreatorAccount(
            platform: .x,
            handle: "@symbiex",
            displayName: "SYMBiEX",
            profileURL: URL(string: "https://x.com/symbiex"),
            followerCount: 880,
            lastSyncedAt: calendar.date(byAdding: .hour, value: -2, to: now),
            platformAccountID: "x-symbiex",
            connectionStatus: .ready,
            syncStatus: .idle,
            pendingImportCount: 2,
            readAccessGranted: true,
            publishAccessGranted: false,
            tags: ["x", "threads", "research"]
        )

        let launchProject = WorkspaceProject(
            title: "Creator OS Launch",
            summary: "Define the first local-first workflow for research, drafts, scheduling, and safe publish preparation.",
            notes: """
            Launch scope:
            - keep captures local first
            - import transcripts only after explicit action
            - turn research into drafts before touching external APIs
            """,
            status: .active,
            linkedAccountIDs: [youtubeAccount.id, xAccount.id],
            publishTargets: [.youtube, .x],
            tagNames: ["launch", "creator-os", "privacy"],
            dueDate: calendar.date(byAdding: .day, value: 7, to: now),
            aiProfile: WorkspaceAIProfile(
                preferredProviderID: ollama.id,
                customSystemPrompt: """
                You are Flannel's local-first launch workspace assistant. Keep this project's answers grounded in selected project notes, local knowledge, and explicit user-provided context. Prefer Local Ollama unless the user intentionally changes the route, and call out any step that would leave this Mac.
                """,
                cloudAccessPolicy: .localOnly,
                localMemoryPolicy: .include,
                indexingRuleNotes: "Index launch notes, drafts, transcripts, and local research sources before expanding to external captures."
            ),
            createdAt: calendar.date(byAdding: .day, value: -3, to: now) ?? now,
            updatedAt: calendar.date(byAdding: .hour, value: -1, to: now) ?? now,
            lastActivityAt: calendar.date(byAdding: .minute, value: -32, to: now) ?? now
        )

        let youtubeSummary = SummaryRecord(
            title: "Core beats",
            text: "The strongest hook is that creators want transcript-backed drafts without moving private notes into browser tabs or cloud bookmark silos.",
            bulletPoints: [
                "Research, transcript, draft, and calendar should stay in one local workspace.",
                "Transcript-backed summaries reduce context loss across long-form video work.",
                "Publishing actions should remain opt-in and visible."
            ],
            sourceLabel: "Local workspace",
            modelLabel: "Manual seed",
            createdAt: calendar.date(byAdding: .hour, value: -5, to: now) ?? now
        )

        let youtubeTranscript = TranscriptRecord(
            status: .available,
            text: """
            Creators lose momentum when saved videos, transcript notes, and publish drafts all live in separate tools.
            A local-first workspace should keep the transcript, hooks, and schedule connected.
            """,
            languageCode: "en",
            sourceLabel: "Imported from local transcript cache",
            importedAt: calendar.date(byAdding: .hour, value: -5, to: now) ?? now,
            updatedAt: calendar.date(byAdding: .hour, value: -2, to: now) ?? now
        )

        let youtubeAsset = LibraryAsset(
            title: "YouTube: Local AI Workflows for Creators",
            kind: .transcript,
            platform: .youtube,
            sourceURL: URL(string: "https://youtube.com/watch?v=local-ai-workflows"),
            sourceIdentifier: "yt-local-ai-workflows",
            summary: youtubeSummary.text,
            summaryStatus: .ready,
            summaryRecords: [youtubeSummary],
            tags: ["youtube", "local-ai", "privacy", "launch"],
            projectID: launchProject.id,
            createdAt: calendar.date(byAdding: .hour, value: -6, to: now) ?? now,
            updatedAt: calendar.date(byAdding: .hour, value: -2, to: now) ?? now,
            capturedAt: calendar.date(byAdding: .hour, value: -6, to: now) ?? now,
            authorName: "SYMBiEX",
            channelTitle: "SYMBiEX",
            transcript: youtubeTranscript,
            notes: "Use this as the reference asset for launch copy and onboarding language.",
            durationSeconds: 754
        )

        let xSummary = SummaryRecord(
            title: "Thread angle",
            text: "The thread should argue that saved posts and videos are only useful if they flow into a project brief and a draft queue.",
            bulletPoints: [
                "Bookmarks are not a workflow.",
                "Summaries need project context.",
                "Drafts should inherit tags from the original capture."
            ],
            sourceLabel: "Local workspace",
            modelLabel: "Manual seed",
            createdAt: calendar.date(byAdding: .hour, value: -3, to: now) ?? now
        )

        let xAsset = LibraryAsset(
            title: "X Thread: Research inboxes should become drafts",
            kind: .research,
            platform: .x,
            sourceURL: URL(string: "https://x.com/symbiex/status/100"),
            sourceIdentifier: "x-100",
            summary: xSummary.text,
            summaryStatus: .ready,
            summaryRecords: [xSummary],
            tags: ["x", "thread", "creator-loop", "drafting"],
            projectID: launchProject.id,
            createdAt: calendar.date(byAdding: .hour, value: -12, to: now) ?? now,
            updatedAt: calendar.date(byAdding: .hour, value: -1, to: now) ?? now,
            capturedAt: calendar.date(byAdding: .hour, value: -12, to: now) ?? now,
            authorName: "SYMBiEX",
            notes: "Use this for short-form launch support copy."
        )

        let noteAsset = LibraryAsset(
            title: "Transcript excerpts: creator workflow pain points",
            kind: .note,
            platform: .internalNote,
            sourceURL: URL(string: "flannel://notes/workflow-pain-points"),
            summary: "Collected clips and notes describing context switching across research, drafting, and distribution.",
            summaryStatus: .ready,
            summaryRecords: [
                SummaryRecord(
                    title: "Pain points",
                    text: "The common failure mode is context fragmentation between source capture, synthesis, and scheduling.",
                    bulletPoints: ["Context switching", "No linked transcript state", "No safe publish handoff"],
                    sourceLabel: "Internal note",
                    createdAt: calendar.date(byAdding: .hour, value: -9, to: now) ?? now
                )
            ],
            tags: ["research", "workflow", "notes"],
            projectID: launchProject.id,
            createdAt: calendar.date(byAdding: .hour, value: -9, to: now) ?? now,
            updatedAt: calendar.date(byAdding: .hour, value: -2, to: now) ?? now,
            capturedAt: calendar.date(byAdding: .hour, value: -9, to: now) ?? now,
            notes: "Internal synthesis note."
        )

        let captureAsset = LibraryAsset(
            title: "Manual capture: platform terms and rate limits",
            kind: .link,
            sourceURL: URL(string: "https://developer.x.com"),
            summary: "Saved locally from the integration rules pass. Publishing remains confirmation-only until explicit credentials exist.",
            summaryStatus: .missing,
            tags: ["manual", "inbox", "platform-rules"],
            projectID: launchProject.id,
            createdAt: calendar.date(byAdding: .minute, value: -45, to: now) ?? now,
            updatedAt: calendar.date(byAdding: .minute, value: -45, to: now) ?? now,
            capturedAt: calendar.date(byAdding: .minute, value: -45, to: now) ?? now,
            notes: "Review before enabling any X write flow."
        )

        let backlogAsset = LibraryAsset(
            title: "YouTube capture: transcript pending",
            kind: .link,
            platform: .youtube,
            sourceURL: URL(string: "https://youtube.com/watch?v=queue-me"),
            sourceIdentifier: "yt-queue-me",
            summary: "Saved locally and waiting for a transcript import request.",
            summaryStatus: .missing,
            tags: ["youtube", "queue", "inbox"],
            projectID: launchProject.id,
            createdAt: calendar.date(byAdding: .minute, value: -20, to: now) ?? now,
            updatedAt: calendar.date(byAdding: .minute, value: -20, to: now) ?? now,
            capturedAt: calendar.date(byAdding: .minute, value: -20, to: now) ?? now,
            channelTitle: "Research Queue",
            transcript: TranscriptRecord(
                status: .queued,
                text: "",
                languageCode: "en",
                sourceLabel: "Awaiting local import",
                importedAt: calendar.date(byAdding: .minute, value: -20, to: now) ?? now,
                updatedAt: calendar.date(byAdding: .minute, value: -20, to: now) ?? now
            )
        )

        let launchDraft = DraftDocument(
            title: "Why local-first creator tooling matters",
            platform: .youtube,
            status: .inProgress,
            body: """
            Hook
            Creators should not have to leak private research context just to turn a video into a publishable draft.

            Problem
            Saved media, summaries, drafts, and scheduling are fragmented.

            Workflow walkthrough
            Show a capture moving into transcript, summary, draft, and calendar.

            CTA
            Keep the whole pipeline local until the final publish step.
            """,
            summary: "Opening script for the product announcement.",
            projectID: launchProject.id,
            scheduledFor: calendar.date(byAdding: .day, value: 3, to: now),
            tags: ["launch", "product", "youtube"],
            createdAt: calendar.date(byAdding: .day, value: -1, to: now) ?? now,
            updatedAt: calendar.date(byAdding: .minute, value: -16, to: now) ?? now,
            sourceAssetIDs: [youtubeAsset.id, noteAsset.id],
            outline: ["Hook", "Workflow gap", "Local-first flow", "CTA"],
            publishNotes: "Hold actual YouTube publish until description and thumbnail are ready.",
            summaryRecords: [youtubeSummary],
            wordCountEstimate: 87,
            requiresReview: true
        )

        let xDraft = DraftDocument(
            title: "Launch thread support copy",
            platform: .x,
            status: .review,
            body: """
            1. Bookmarks are not a workflow.
            2. Saved videos should become summaries, not forgotten tabs.
            3. Flannel keeps transcript, draft, and schedule together locally.
            """,
            summary: "Companion thread for the launch video.",
            projectID: launchProject.id,
            scheduledFor: calendar.date(byAdding: .day, value: 3, to: now),
            tags: ["launch", "x", "thread"],
            createdAt: calendar.date(byAdding: .hour, value: -22, to: now) ?? now,
            updatedAt: calendar.date(byAdding: .hour, value: -1, to: now) ?? now,
            sourceAssetIDs: [xAsset.id, noteAsset.id],
            outline: ["Problem", "System", "Promise"],
            publishNotes: "Pair with the YouTube release window.",
            summaryRecords: [xSummary],
            wordCountEstimate: 34
        )

        let publishVideoEntry = PublishingCalendarEntry(
            title: "Publish launch video",
            startAt: launchDraft.scheduledFor ?? now,
            destination: .calendar,
            projectID: launchProject.id,
            draftID: launchDraft.id,
            notes: "Coordinate YouTube publish with X thread and exported show notes.",
            platform: .youtube,
            status: .scheduled,
            reminderMinutesBefore: 90,
            createdAt: calendar.date(byAdding: .hour, value: -8, to: now) ?? now,
            updatedAt: calendar.date(byAdding: .hour, value: -1, to: now) ?? now
        )

        let publishThreadEntry = PublishingCalendarEntry(
            title: "Post launch support thread",
            startAt: xDraft.scheduledFor ?? now,
            destination: .calendar,
            projectID: launchProject.id,
            draftID: xDraft.id,
            notes: "Keep as confirmation-only until final copy is reviewed.",
            platform: .x,
            status: .draft,
            reminderMinutesBefore: 45,
            createdAt: calendar.date(byAdding: .hour, value: -8, to: now) ?? now,
            updatedAt: calendar.date(byAdding: .hour, value: -30, to: now) ?? now
        )

        let digestAutomation = WorkspaceAutomation(
            title: "Daily research digest",
            detail: "Summarize newly captured sources locally each morning.",
            cadence: .daily,
            requiresConfirmation: false,
            linkedDestination: .library,
            linkedProjectID: launchProject.id,
            actionKind: .generateSummary,
            lastRunState: .succeeded,
            lastRunAt: calendar.date(byAdding: .hour, value: -7, to: now),
            nextRunAt: calendar.date(byAdding: .day, value: 1, to: now),
            lastResultMessage: "Summarized 2 sources with no external calls."
        )

        let transcriptAutomation = WorkspaceAutomation(
            title: "Transcript queue sweep",
            detail: "Find YouTube captures that still need transcript import.",
            cadence: .hourly,
            requiresConfirmation: false,
            linkedDestination: .youtube,
            linkedProjectID: launchProject.id,
            actionKind: .importTranscript,
            lastRunState: .queued,
            lastRunAt: calendar.date(byAdding: .minute, value: -25, to: now),
            nextRunAt: calendar.date(byAdding: .minute, value: 35, to: now),
            lastResultMessage: "1 video still queued for transcript import."
        )

        let calendarAutomation = WorkspaceAutomation(
            title: "Weekly content calendar",
            detail: "Prepare a proposed posting plan from active drafts and summaries.",
            cadence: .weekly,
            requiresConfirmation: true,
            linkedDestination: .calendar,
            linkedProjectID: launchProject.id,
            actionKind: .scheduleDraft,
            lastRunState: .needsConfirmation,
            nextRunAt: calendar.date(byAdding: .day, value: 6, to: now),
            lastResultMessage: "Confirmation required before scheduling external publish windows."
        )

        let assistantThread = AssistantThread(
            title: "Workspace Copilot",
            mode: .workspaceCopilot,
            messages: [
                AssistantMessage(
                    role: .system,
                    text: "You are Flannel's workspace copilot. Use the selected destination, project, draft, library, automation, and settings context before answering."
                ),
                AssistantMessage(
                    role: .assistant,
                    text: "The launch workspace is loaded locally. Transcript state, summaries, and safe action history are available without touching external APIs.",
                    createdAt: calendar.date(byAdding: .minute, value: -8, to: now) ?? now,
                    referencedEntityIDs: [launchProject.id, launchDraft.id, youtubeAsset.id]
                )
            ],
            pinnedProjectID: launchProject.id,
            pinnedDraftID: launchDraft.id,
            pinnedAssetID: youtubeAsset.id,
            pinnedCalendarEntryID: publishVideoEntry.id,
            createdAt: calendar.date(byAdding: .day, value: -2, to: now) ?? now,
            updatedAt: calendar.date(byAdding: .minute, value: -8, to: now) ?? now
        )

        let actions = [
            LocalActionRecord(
                kind: .captureURL,
                title: "Saved pasted URL locally",
                detail: "Stored the X developer policy link in Inbox without contacting the network.",
                status: .completed,
                destination: .inbox,
                relatedProjectID: launchProject.id,
                relatedAssetID: captureAsset.id,
                completedAt: calendar.date(byAdding: .minute, value: -45, to: now)
            ),
            LocalActionRecord(
                kind: .importTranscript,
                title: "Imported transcript cache",
                detail: "Attached a local transcript to the launch reference video.",
                status: .completed,
                destination: .youtube,
                relatedProjectID: launchProject.id,
                relatedAssetID: youtubeAsset.id,
                completedAt: calendar.date(byAdding: .hour, value: -5, to: now)
            ),
            LocalActionRecord(
                kind: .scheduleDraft,
                title: "Prepare publish schedule",
                detail: "Calendar automation wants confirmation before it proposes live posting windows.",
                status: .requiresConfirmation,
                destination: .calendar,
                relatedProjectID: launchProject.id,
                relatedDraftID: xDraft.id,
                automationID: calendarAutomation.id,
                requiresConfirmation: true
            )
        ]

        let tags = [
            WorkspaceTag(name: "launch", colorName: "red", usageCount: 6),
            WorkspaceTag(name: "youtube", colorName: "orange", usageCount: 3),
            WorkspaceTag(name: "x", colorName: "blue", usageCount: 3),
            WorkspaceTag(name: "privacy", colorName: "green", usageCount: 2),
            WorkspaceTag(name: "inbox", colorName: "gray", usageCount: 2)
        ]

        var hydratedProject = launchProject
        hydratedProject.assetIDs = [youtubeAsset.id, xAsset.id, noteAsset.id, captureAsset.id, backlogAsset.id]
        hydratedProject.draftIDs = [launchDraft.id, xDraft.id]
        hydratedProject.calendarEntryIDs = [publishVideoEntry.id, publishThreadEntry.id]
        hydratedProject.automationIDs = [digestAutomation.id, transcriptAutomation.id, calendarAutomation.id]

        let preferences = WorkspacePreferences(
            preferredProviderID: ollama.id,
            lastOpenedAt: now,
            defaultDestination: .home,
            showsRightSidebar: true,
            leftSidebarWidth: 248,
            rightSidebarWidth: 368,
            automationsEnabled: true,
            confirmBeforeExternalActions: true,
            allowCloudProviders: false,
            defaultTranscriptLanguageCode: "en",
            draftExportDirectory: "~/Documents/Flannel/Exports",
            localStorageLabel: "~/Library/Application Support/Flannel",
            safeMode: true
        )

        return Item(
            schemaVersion: 2,
            timestamp: now,
            updatedAt: now,
            selectedDestination: .home,
            selectedProjectID: hydratedProject.id,
            selectedDraftID: launchDraft.id,
            selectedAssetID: youtubeAsset.id,
            selectedCalendarEntryID: publishVideoEntry.id,
            selectedAssistantThreadID: assistantThread.id,
            accounts: [youtubeAccount, xAccount],
            providerConfigurations: [ollama, openAI],
            libraryAssets: [backlogAsset, captureAsset, youtubeAsset, xAsset, noteAsset],
            projects: [hydratedProject],
            drafts: [launchDraft, xDraft],
            calendarEntries: [publishVideoEntry, publishThreadEntry],
            assistantThreads: [assistantThread],
            automations: [digestAutomation, transcriptAutomation, calendarAutomation],
            localActionHistory: actions,
            tags: tags,
            preferences: preferences
        )
    }
}
