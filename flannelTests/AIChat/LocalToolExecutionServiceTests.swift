//
//  LocalToolExecutionServiceTests.swift
//  flannelTests
//

import Testing
import Foundation
@testable import flannel

struct LocalToolExecutionServiceTests {
    @Test("Local file read uses the requested path before selected file context")
    func localFileReadUsesRequestedPathBeforeSelectedFileContext() throws {
        let service = LocalToolExecutionService()
        let tool = ToolConfiguration(
            kind: .localFileRead,
            title: "Read Files",
            detail: "Read explicit paths",
            permissionPolicy: .alwaysAllow,
            isEnabled: true
        )
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flannel-file-read-\(UUID().uuidString).txt")
            .standardizedFileURL
        try "Requested path content".write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let context = LocalToolExecutionContext(
            tool: tool,
            query: fileURL.path,
            fileText: "Wrong selected file content"
        )

        let result = service.run(context)

        #expect(result.status == .completed)
        #expect(result.output.contains(fileURL.path))
        #expect(result.output.contains("Requested path content"))
        #expect(result.output.contains("Wrong selected file content") == false)
    }

    @Test("Local file read rejects a directory path")
    func localFileReadRejectsDirectoryPath() {
        let service = LocalToolExecutionService()
        let tool = ToolConfiguration(
            kind: .localFileRead,
            title: "Read Files",
            detail: "Read explicit paths",
            permissionPolicy: .alwaysAllow,
            isEnabled: true
        )
        let context = LocalToolExecutionContext(tool: tool, query: FileManager.default.temporaryDirectory.path)

        let result = service.run(context)

        #expect(result.status == .blocked)
        #expect(result.output.contains("target is a directory"))
    }

    @Test("Local file read requires a path without selected file context")
    func localFileReadRequiresPathWithoutSelectedFileContext() {
        let service = LocalToolExecutionService()
        let tool = ToolConfiguration(
            kind: .localFileRead,
            title: "Read Files",
            detail: "Read explicit paths",
            permissionPolicy: .alwaysAllow,
            isEnabled: true
        )
        let context = LocalToolExecutionContext(tool: tool)

        let result = service.run(context)

        #expect(result.status == .blocked)
        #expect(result.output.contains("requires a target path"))
    }

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
