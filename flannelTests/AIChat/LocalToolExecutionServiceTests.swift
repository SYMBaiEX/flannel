//
//  LocalToolExecutionServiceTests.swift
//  flannelTests
//

import Testing
@testable import flannel

struct LocalToolExecutionServiceTests {
    @Test("Local tool permission gate blocks disabled tools")
    func permissionGateBlocksDisabledTools() throws {
        let service = LocalToolExecutionService()
        let tool = ToolConfiguration(
            kind: .webSearch,
            title: "Web search",
            detail: "Local-only network placeholder",
            permissionPolicy: .alwaysAllow,
            isEnabled: false,
            requiresNetwork: true
        )
        let context = LocalToolExecutionContext(tool: tool, query: "local-first")

        let result = try #require(service.permissionGate(for: context))

        #expect(result.status == .blocked)
        #expect(result.output.contains("is disabled in Tools"))
        #expect(result.usedNetwork == false)
    }

    @Test("Local tool permission gate blocks tools set to local-only policy when network or writes are required")
    func permissionGateBlocksLocalOnlyPolicyForProtectedTools() throws {
        let service = LocalToolExecutionService()
        let tool = ToolConfiguration(
            kind: .localFileWrite,
            title: "Local file write",
            detail: "Writes local files by policy",
            permissionPolicy: .localOnly,
            isEnabled: true,
            requiresNetwork: false,
            canModifyFiles: true
        )
        let context = LocalToolExecutionContext(tool: tool, query: "append log line")

        let result = try #require(service.permissionGate(for: context))

        #expect(result.status == .blocked)
        #expect(result.output == "Local file write is restricted to local read/query behavior by policy.")
        #expect(result.modifiedFiles == false)
    }

    @Test("Local tool permission gate requires approval for ask-every-time policy")
    func permissionGateRequiresApprovalForAskEveryTime() throws {
        let service = LocalToolExecutionService()
        let tool = ToolConfiguration(
            kind: .terminal,
            title: "Terminal",
            detail: "Unsafe command execution",
            permissionPolicy: .askEveryTime,
            isEnabled: true
        )
        let context = LocalToolExecutionContext(tool: tool, query: "printf hello")

        let result = try #require(service.permissionGate(for: context))

        #expect(result.status == .requiresApproval)
        #expect(result.requiresApproval)
        #expect(result.output.contains("requires explicit approval"))
    }
}
