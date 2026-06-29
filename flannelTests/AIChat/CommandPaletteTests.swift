//
//  CommandPaletteTests.swift
//  flannelTests
//

import Testing
@testable import flannel

struct CommandPaletteTests {
    @Test("Command search handles case and whitespace normalization")
    func commandSearchHandlesCaseAndWhitespace() throws {
        let context = FlannelCommandContext(
            hasCurrentThread: true,
            canSendMessage: true,
            isStreaming: false,
            isDiscoveringModels: false,
            canCompareCurrentPrompt: false,
            canRunComparison: false,
            localOnlyMode: true,
            inspectorVisible: false
        )
        let commands = FlannelCommand.defaultCommands(context: context)
        let knowledge = try #require(commands.first { $0.id == .openKnowledge })

        #expect(knowledge.matches("   OPEn   Knowledge  "))
        #expect(knowledge.matches("rag settings"))
    }

    @Test("Command search requires all requested terms to match")
    func commandSearchRequiresAllTerms() throws {
        let context = FlannelCommandContext(
            hasCurrentThread: true,
            canSendMessage: true,
            isStreaming: false,
            isDiscoveringModels: false,
            canCompareCurrentPrompt: false,
            canRunComparison: false,
            localOnlyMode: true,
            inspectorVisible: false
        )
        let commands = FlannelCommand.defaultCommands(context: context)
        let knowledge = try #require(commands.first { $0.id == .openKnowledge })

        #expect(knowledge.matches("rag settings") == true)
        #expect(knowledge.matches("rag settings archive") == false)
    }

    @Test("Empty command query matches all commands")
    func commandSearchMatchesAllWhenQueryIsBlank() throws {
        let context = FlannelCommandContext(
            hasCurrentThread: true,
            canSendMessage: true,
            isStreaming: false,
            isDiscoveringModels: false,
            canCompareCurrentPrompt: false,
            canRunComparison: false,
            localOnlyMode: true,
            inspectorVisible: false
        )
        let commands = FlannelCommand.defaultCommands(context: context)
        let knowledge = try #require(commands.first { $0.id == .openKnowledge })

        #expect(knowledge.matches(" "))
        #expect(commands.allSatisfy { $0.matches(" \t\n") })
    }

    @Test("Command search matches title, category, subtitle, and keywords")
    func commandSearchMatchesRelevantText() {
        let context = FlannelCommandContext(
            hasCurrentThread: true,
            canSendMessage: true,
            isStreaming: false,
            isDiscoveringModels: false,
            canCompareCurrentPrompt: true,
            canRunComparison: true,
            localOnlyMode: true,
            inspectorVisible: true
        )
        let commands = FlannelCommand.defaultCommands(context: context)

        #expect(commands.filter { $0.matches("ollama") }.contains { $0.id == .discoverModels })
        #expect(commands.filter { $0.matches("export pdf") }.map(\.id) == [.exportPDF])
        #expect(commands.filter { $0.matches("rag") }.contains { $0.id == .openKnowledge })
        #expect(commands.filter { $0.matches("side provider") }.contains { $0.id == .comparePrompt })
    }

    @Test("Command enablement reflects live chat and model state")
    func commandEnablementReflectsContext() {
        let context = FlannelCommandContext(
            hasCurrentThread: false,
            canSendMessage: false,
            isStreaming: true,
            isDiscoveringModels: true,
            canCompareCurrentPrompt: false,
            canRunComparison: false,
            localOnlyMode: false,
            inspectorVisible: false
        )
        let commands = FlannelCommand.defaultCommands(context: context)

        #expect(commands.first { $0.id == .sendMessage }?.isEnabled == false)
        #expect(commands.first { $0.id == .stopStreaming }?.isEnabled == true)
        #expect(commands.first { $0.id == .comparePrompt }?.isEnabled == false)
        #expect(commands.first { $0.id == .discoverModels }?.isEnabled == false)
        #expect(commands.first { $0.id == .exportMarkdown }?.isEnabled == false)
        #expect(commands.first { $0.id == .showInspector }?.isEnabled == true)
    }

    @Test("Knowledge rebuild commands reflect RAG source state")
    func knowledgeRebuildCommandsReflectSourceState() throws {
        let emptyContext = FlannelCommandContext(
            hasCurrentThread: true,
            canSendMessage: false,
            isStreaming: false,
            isDiscoveringModels: false,
            canCompareCurrentPrompt: false,
            canRunComparison: false,
            localOnlyMode: true,
            inspectorVisible: true,
            hasKnowledgeSources: false,
            hasQueuedKnowledgeSources: false
        )
        let queuedContext = FlannelCommandContext(
            hasCurrentThread: true,
            canSendMessage: false,
            isStreaming: false,
            isDiscoveringModels: false,
            canCompareCurrentPrompt: false,
            canRunComparison: false,
            localOnlyMode: true,
            inspectorVisible: true,
            hasKnowledgeSources: true,
            hasQueuedKnowledgeSources: true
        )

        let emptyCommands = FlannelCommand.defaultCommands(context: emptyContext)
        let queuedCommands = FlannelCommand.defaultCommands(context: queuedContext)
        let emptyQueued = try #require(emptyCommands.first { $0.id == .rebuildQueuedKnowledge })
        let emptyAll = try #require(emptyCommands.first { $0.id == .rebuildAllKnowledge })
        let queuedRebuild = try #require(queuedCommands.first { $0.id == .rebuildQueuedKnowledge })
        let allRebuild = try #require(queuedCommands.first { $0.id == .rebuildAllKnowledge })

        #expect(emptyQueued.isEnabled == false)
        #expect(emptyAll.isEnabled == false)
        #expect(queuedRebuild.isEnabled)
        #expect(allRebuild.isEnabled)
        #expect(queuedRebuild.matches("rag queued refresh"))
        #expect(allRebuild.matches("rebuild embeddings"))
    }

    @Test("Local-only command title reflects the current privacy mode")
    func localOnlyCommandReflectsPrivacyMode() throws {
        let enabledContext = FlannelCommandContext(
            hasCurrentThread: true,
            canSendMessage: false,
            isStreaming: false,
            isDiscoveringModels: false,
            canCompareCurrentPrompt: false,
            canRunComparison: false,
            localOnlyMode: true,
            inspectorVisible: true
        )
        let disabledContext = FlannelCommandContext(
            hasCurrentThread: true,
            canSendMessage: false,
            isStreaming: false,
            isDiscoveringModels: false,
            canCompareCurrentPrompt: false,
            canRunComparison: false,
            localOnlyMode: false,
            inspectorVisible: true
        )

        let enabledTitle = try #require(FlannelCommand.defaultCommands(context: enabledContext).first { $0.id == .toggleLocalOnly }?.title)
        let disabledTitle = try #require(FlannelCommand.defaultCommands(context: disabledContext).first { $0.id == .toggleLocalOnly }?.title)

        #expect(enabledTitle == "Disable Local-Only Mode")
        #expect(disabledTitle == "Enable Local-Only Mode")
    }

    @Test("Cloud provider command reflects local and cloud privacy boundaries")
    func cloudProviderCommandReflectsPrivacyBoundary() throws {
        let localOnlyContext = FlannelCommandContext(
            hasCurrentThread: true,
            canSendMessage: false,
            isStreaming: false,
            isDiscoveringModels: false,
            canCompareCurrentPrompt: false,
            canRunComparison: false,
            localOnlyMode: true,
            allowCloudProviders: false,
            inspectorVisible: true
        )
        let localAndCLIContext = FlannelCommandContext(
            hasCurrentThread: true,
            canSendMessage: false,
            isStreaming: false,
            isDiscoveringModels: false,
            canCompareCurrentPrompt: false,
            canRunComparison: false,
            localOnlyMode: false,
            allowCloudProviders: false,
            inspectorVisible: true
        )
        let cloudAllowedContext = FlannelCommandContext(
            hasCurrentThread: true,
            canSendMessage: false,
            isStreaming: false,
            isDiscoveringModels: false,
            canCompareCurrentPrompt: false,
            canRunComparison: false,
            localOnlyMode: false,
            allowCloudProviders: true,
            inspectorVisible: true
        )

        let localOnlyCommand = try #require(FlannelCommand.defaultCommand(.toggleCloudProviders, context: localOnlyContext))
        let localAndCLICommand = try #require(FlannelCommand.defaultCommand(.toggleCloudProviders, context: localAndCLIContext))
        let cloudAllowedCommand = try #require(FlannelCommand.defaultCommand(.toggleCloudProviders, context: cloudAllowedContext))

        #expect(localOnlyCommand.title == "Allow Cloud API Providers")
        #expect(localOnlyCommand.subtitle.contains("Turn off local-only mode"))
        #expect(localOnlyCommand.systemImage == "network")
        #expect(localOnlyCommand.keyEquivalent == "⌥⌘C")
        #expect(localOnlyCommand.matches("byok api key"))

        #expect(localAndCLICommand.title == "Allow Cloud API Providers")
        #expect(localAndCLICommand.matches("cloud providers"))

        #expect(cloudAllowedCommand.title == "Block Cloud API Providers")
        #expect(cloudAllowedCommand.subtitle.contains("blocking external API-key providers"))
        #expect(cloudAllowedCommand.systemImage == "network.slash")
        #expect(cloudAllowedCommand.isEnabled)
    }

    @Test("Routing policy commands are searchable and reflect active policy")
    func routingPolicyCommandsReflectActivePolicy() throws {
        let context = FlannelCommandContext(
            hasCurrentThread: true,
            canSendMessage: false,
            isStreaming: false,
            isDiscoveringModels: false,
            canCompareCurrentPrompt: false,
            canRunComparison: false,
            localOnlyMode: true,
            inspectorVisible: true,
            providerRoutingPolicy: .fastest
        )
        let commands = FlannelCommand.defaultCommands(context: context)

        let fastest = try #require(commands.first { $0.id == .setRoutingFastest })
        let localFirst = try #require(commands.first { $0.id == .setRoutingLocalFirst })
        let bestAvailable = try #require(commands.first { $0.id == .setRoutingBestAvailable })

        #expect(fastest.isEnabled == false)
        #expect(fastest.systemImage == "checkmark.circle")
        #expect(fastest.subtitle.contains("active"))
        #expect(localFirst.isEnabled)
        #expect(localFirst.matches("local first routing"))
        #expect(bestAvailable.matches("best model policy"))

        for policy in ProviderRoutingPolicy.allCases {
            #expect(FlannelCommandID.routingCommandID(for: policy).routingPolicy == policy)
        }
    }

    @Test("Native menu commands are represented in the shared command catalog")
    func nativeMenuCommandsUseSharedCommandCatalog() throws {
        let visibleInspectorContext = FlannelCommandContext(
            hasCurrentThread: true,
            canSendMessage: false,
            isStreaming: false,
            isDiscoveringModels: false,
            canCompareCurrentPrompt: false,
            canRunComparison: false,
            localOnlyMode: true,
            inspectorVisible: true
        )
        let hiddenInspectorContext = FlannelCommandContext(
            hasCurrentThread: true,
            canSendMessage: false,
            isStreaming: false,
            isDiscoveringModels: false,
            canCompareCurrentPrompt: false,
            canRunComparison: false,
            localOnlyMode: true,
            inspectorVisible: false
        )

        let importCommand = try #require(FlannelCommand.defaultCommand(.importChat, context: visibleInspectorContext))
        let paletteCommand = try #require(FlannelCommand.defaultCommand(.openCommandPalette, context: visibleInspectorContext))
        let settingsCommand = try #require(FlannelCommand.defaultCommand(.openSettings, context: visibleInspectorContext))
        let localOnlyCommand = try #require(FlannelCommand.defaultCommand(.toggleLocalOnly, context: visibleInspectorContext))
        let cloudProviderCommand = try #require(FlannelCommand.defaultCommand(.toggleCloudProviders, context: visibleInspectorContext))
        let focusChat = try #require(FlannelCommand.defaultCommand(.focusChat, context: visibleInspectorContext))
        let focusChatWhenHidden = try #require(FlannelCommand.defaultCommand(.focusChat, context: hiddenInspectorContext))
        let showInspector = try #require(FlannelCommand.defaultCommand(.showInspector, context: hiddenInspectorContext))

        #expect(importCommand.keyEquivalent == "⇧⌘I")
        #expect(importCommand.matches("restore backup"))
        #expect(paletteCommand.keyEquivalent == "⌘K")
        #expect(paletteCommand.matches("keyboard actions"))
        #expect(settingsCommand.keyEquivalent == "⌘,")
        #expect(settingsCommand.matches("preferences privacy"))
        #expect(localOnlyCommand.keyEquivalent == "⌥⌘L")
        #expect(localOnlyCommand.matches("privacy network"))
        #expect(cloudProviderCommand.keyEquivalent == "⌥⌘C")
        #expect(cloudProviderCommand.matches("cloud provider byok"))
        #expect(focusChat.isEnabled)
        #expect(focusChatWhenHidden.isEnabled == false)
        #expect(showInspector.isEnabled)
    }
}
