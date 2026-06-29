//
//  LocalToolExecutionService.swift
//  flannel
//
//  Created by OpenAI Codex on 6/28/26.
//

import Foundation

struct LocalToolExecutionContext: Sendable, Hashable {
    var tool: ToolConfiguration
    var query: String
    var localOnlyMode: Bool
    var workspaceSummary: String
    var retrievalPacket: LocalKnowledgeRetrievalPacket?
    var webPageText: String?
    var capturedWebPage: CapturedWebPage?
    var fileText: String?

    init(
        tool: ToolConfiguration,
        query: String = "",
        localOnlyMode: Bool = true,
        workspaceSummary: String = "",
        retrievalPacket: LocalKnowledgeRetrievalPacket? = nil,
        webPageText: String? = nil,
        capturedWebPage: CapturedWebPage? = nil,
        fileText: String? = nil
    ) {
        self.tool = tool
        self.query = query
        self.localOnlyMode = localOnlyMode
        self.workspaceSummary = workspaceSummary
        self.retrievalPacket = retrievalPacket
        self.webPageText = webPageText
        self.capturedWebPage = capturedWebPage
        self.fileText = fileText
    }
}

struct LocalToolExecutionService: Sendable {
    private let commandTimeout: TimeInterval = 12
    private let maximumOutputCharacters = 24_000

    func run(_ context: LocalToolExecutionContext) -> LocalToolExecutionResult {
        if let gate = permissionGate(for: context) {
            return gate
        }

        let tool = context.tool
        let query = context.query.trimmingCharacters(in: .whitespacesAndNewlines)

        switch tool.kind {
        case .workspaceSearch:
            return completed(
                context,
                output: context.workspaceSummary.isEmpty
                    ? "No workspace context is currently available."
                    : "Workspace search for \"\(queryOrDefault(query))\"\n\n\(context.workspaceSummary)"
            )

        case .ragRetrieval:
            guard let packet = context.retrievalPacket, !packet.isEmpty else {
                return completed(
                    context,
                    output: "No local RAG matches were found for \"\(queryOrDefault(query))\"."
                )
            }
            let lines = packet.results.enumerated().map { index, result in
                "\(index + 1). \(result.chunk.citationTitle): \(result.snippet)"
            }
            return completed(
                context,
                output: "RAG retrieval for \"\(packet.query)\"\n" + lines.joined(separator: "\n")
            )

        case .webPageReader:
            if let page = context.capturedWebPage {
                return completed(
                    context,
                    usedNetwork: true,
                    output: Self.formattedCapturedWebPage(page)
                )
            }

            guard let text = context.webPageText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                return unavailable(
                    context,
                    output: "No selected local web page capture is available to read. Enter an http or https URL to fetch a live page."
                )
            }
            return completed(context, output: "Local web page reader\n\n\(text)")

        case .localFileRead:
            guard let text = context.fileText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                return unavailable(
                    context,
                    output: "No readable selected file or file knowledge source is available."
                )
            }
            return completed(context, output: "Local file read\n\n\(text)")

        case .localFileWrite:
            return writeLocalFile(context, query: query)

        case .webSearch:
            return unavailable(
                context,
                usedNetwork: false,
                output: "\(tool.title) is configured for live network execution. Run it from the async tool path so Flannel can resolve Keychain credentials and provider transport safely."
            )

        case .github:
            return unavailable(
                context,
                usedNetwork: false,
                output: "\(tool.title) is configured for live network execution. Run it from the async tool path so Flannel can resolve optional Keychain credentials and provider transport safely."
            )

        case .notion:
            return unavailable(
                context,
                usedNetwork: false,
                output: "\(tool.title) is configured for live Notion API execution. Run it from the async tool path so Flannel can resolve Keychain credentials and provider transport safely."
            )

        case .youtube:
            return unavailable(
                context,
                usedNetwork: false,
                output: "\(tool.title) is configured for live YouTube Data API execution. Run it from the async tool path so Flannel can resolve Keychain credentials and provider transport safely."
            )

        case .x:
            return unavailable(
                context,
                usedNetwork: false,
                output: "\(tool.title) is configured for live X API execution. Run it from the async tool path so Flannel can resolve Keychain credentials and provider transport safely."
            )

        case .browserAutomation:
            return unavailable(
                context,
                usedNetwork: false,
                output: "\(tool.title) is configured for live default-browser opening. Run it from the async tool path so Flannel can apply network approval before opening a URL or browser search."
            )

        case .terminal:
            return runTerminalCommand(context, command: query)

        case .codeExecution:
            return runCodeSnippet(context, request: query)
        }
    }

    func permissionGate(for context: LocalToolExecutionContext) -> LocalToolExecutionResult? {
        let tool = context.tool

        guard tool.isEnabled else {
            return LocalToolExecutionResult(
                toolID: tool.id,
                toolKind: tool.kind,
                title: tool.title,
                query: context.query,
                status: .blocked,
                output: "\(tool.title) is disabled in Tools.",
                usedNetwork: false,
                modifiedFiles: false
            )
        }

        if context.localOnlyMode && tool.requiresNetwork {
            return LocalToolExecutionResult(
                toolID: tool.id,
                toolKind: tool.kind,
                title: tool.title,
                query: context.query,
                status: .blocked,
                output: "\(tool.title) requires network access and is blocked while Local-Only mode is on.",
                usedNetwork: false,
                modifiedFiles: false
            )
        }

        switch tool.permissionPolicy {
        case .deny:
            return LocalToolExecutionResult(
                toolID: tool.id,
                toolKind: tool.kind,
                title: tool.title,
                query: context.query,
                status: .denied,
                output: "\(tool.title) is denied by the current permission policy.",
                usedNetwork: false,
                modifiedFiles: false
            )

        case .localOnly where tool.requiresNetwork || tool.canModifyFiles:
            return LocalToolExecutionResult(
                toolID: tool.id,
                toolKind: tool.kind,
                title: tool.title,
                query: context.query,
                status: .blocked,
                output: "\(tool.title) is restricted to local read/query behavior by policy.",
                usedNetwork: false,
                modifiedFiles: false
            )

        case .askEveryTime:
            return approvalRequired(
                context,
                output: "\(tool.title) requires explicit approval before this run."
            )

        case .alwaysAllow, .localOnly:
            return nil
        }
    }

    private func completed(
        _ context: LocalToolExecutionContext,
        usedNetwork: Bool = false,
        modifiedFiles: Bool = false,
        output: String
    ) -> LocalToolExecutionResult {
        LocalToolExecutionResult(
            toolID: context.tool.id,
            toolKind: context.tool.kind,
            title: context.tool.title,
            query: context.query,
            status: .completed,
            output: output,
            usedNetwork: usedNetwork,
            modifiedFiles: modifiedFiles
        )
    }

    private func approvalRequired(
        _ context: LocalToolExecutionContext,
        output: String
    ) -> LocalToolExecutionResult {
        LocalToolExecutionResult(
            toolID: context.tool.id,
            toolKind: context.tool.kind,
            title: context.tool.title,
            query: context.query,
            status: .requiresApproval,
            output: output,
            requiresApproval: true,
            usedNetwork: context.tool.requiresNetwork,
            modifiedFiles: context.tool.canModifyFiles
        )
    }

    private func unavailable(
        _ context: LocalToolExecutionContext,
        usedNetwork: Bool = false,
        output: String
    ) -> LocalToolExecutionResult {
        LocalToolExecutionResult(
            toolID: context.tool.id,
            toolKind: context.tool.kind,
            title: context.tool.title,
            query: context.query,
            status: .unavailable,
            output: output,
            usedNetwork: usedNetwork,
            modifiedFiles: false
        )
    }

    private func blocked(
        _ context: LocalToolExecutionContext,
        output: String
    ) -> LocalToolExecutionResult {
        LocalToolExecutionResult(
            toolID: context.tool.id,
            toolKind: context.tool.kind,
            title: context.tool.title,
            query: context.query,
            status: .blocked,
            output: output,
            usedNetwork: false,
            modifiedFiles: false
        )
    }

    private func queryOrDefault(_ query: String) -> String {
        query.isEmpty ? "current workspace" : query
    }

    private static func formattedCapturedWebPage(_ page: CapturedWebPage) -> String {
        let statusLine = page.statusCode.map { "HTTP \($0)" } ?? "HTTP status unavailable"
        let contentType = page.contentType?.trimmingCharacters(in: .whitespacesAndNewlines)
        let typeLine = contentType?.isEmpty == false ? "\nContent-Type: \(contentType!)" : ""
        return """
        Live web page reader
        Title: \(page.title)
        URL: \(page.url.absoluteString)
        Status: \(statusLine)\(typeLine)
        Captured: \(page.capturedAt.formatted(date: .abbreviated, time: .shortened))

        Excerpt:
        \(page.excerpt)

        Readable text:
        \(page.text)
        """
    }

    private func writeLocalFile(_ context: LocalToolExecutionContext, query: String) -> LocalToolExecutionResult {
        let request = parseLocalFileWriteRequest(query)
        guard let targetPath = request.targetPath, !targetPath.isEmpty else {
            return blocked(
                context,
                output: """
                File write requires a target path on the first line and content below it.

                Example:
                ~/Documents/flannel-note.md
                ---
                Notes written by Flannel.
                """
            )
        }

        guard let content = request.content, !content.isEmpty else {
            return blocked(
                context,
                output: "File write requires content after the target path. No file was changed."
            )
        }

        guard targetPath.range(of: "\0") == nil else {
            return blocked(context, output: "File write rejected an invalid path. No file was changed.")
        }

        let expandedPath = (targetPath as NSString).expandingTildeInPath
        let targetURL: URL
        if let parsedURL = URL(string: expandedPath), parsedURL.isFileURL {
            targetURL = parsedURL.standardizedFileURL
        } else {
            targetURL = URL(fileURLWithPath: expandedPath).standardizedFileURL
        }

        guard !targetURL.hasDirectoryPath else {
            return blocked(context, output: "File write target is a directory. Choose a file path instead.")
        }

        let parentURL = targetURL.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parentURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return blocked(context, output: "File write parent folder does not exist: \(parentURL.path)")
        }

        guard FileManager.default.isWritableFile(atPath: parentURL.path) else {
            return blocked(context, output: "File write parent folder is not writable: \(parentURL.path)")
        }

        do {
            try content.write(to: targetURL, atomically: true, encoding: .utf8)
            let byteCount = Data(content.utf8).count
            return completed(
                context,
                modifiedFiles: true,
                output: "Wrote \(byteCount) bytes to \(targetURL.path)."
            )
        } catch {
            return unavailable(
                context,
                output: "File write failed for \(targetURL.path): \(error.localizedDescription)"
            )
        }
    }

    private func parseLocalFileWriteRequest(_ query: String) -> (targetPath: String?, content: String?) {
        var lines = query
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeFirst()
        }

        guard let firstLine = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !firstLine.isEmpty else {
            return (nil, nil)
        }

        let targetPath = strippingPathPrefix(from: firstLine)
        lines.removeFirst()

        if lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---" {
            lines.removeFirst()
        }

        let content = lines.joined(separator: "\n")
        return (targetPath, content.trimmingCharacters(in: .newlines))
    }

    private func strippingPathPrefix(from line: String) -> String {
        let prefixes = ["path:", "file:"]
        let lowercasedLine = line.lowercased()
        for prefix in prefixes where lowercasedLine.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return line
    }

    private func runTerminalCommand(_ context: LocalToolExecutionContext, command rawCommand: String) -> LocalToolExecutionResult {
        let request = parseTerminalRequest(rawCommand)
        guard !request.command.isEmpty else {
            return blocked(
                context,
                output: """
                Terminal requires a command to run.

                Optional first line:
                cwd: ~/Projects/example
                """
            )
        }

        guard request.command.range(of: "\0") == nil else {
            return blocked(context, output: "Terminal command rejected invalid null-byte input.")
        }

        let cwd = resolvedWorkingDirectory(from: request.cwd)
        let result = runProcess(
            executablePath: "/bin/zsh",
            arguments: ["-lc", request.command],
            currentDirectory: cwd,
            timeout: commandTimeout
        )
        return completed(
            context,
            modifiedFiles: context.tool.canModifyFiles,
            output: formattedProcessOutput(
                title: "Terminal command",
                command: request.command,
                workingDirectory: cwd.path,
                result: result
            )
        )
    }

    private func runCodeSnippet(_ context: LocalToolExecutionContext, request rawRequest: String) -> LocalToolExecutionResult {
        let request = parseCodeExecutionRequest(rawRequest)
        guard let language = request.language else {
            return blocked(
                context,
                output: """
                Code execution requires a language on the first line.

                Supported: zsh, bash, python, javascript, swift
                """
            )
        }

        guard !request.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return blocked(context, output: "Code execution requires source code after the language line.")
        }

        let normalizedLanguage = language.lowercased()
        guard let runner = codeRunner(for: normalizedLanguage) else {
            return blocked(context, output: "Unsupported code execution language: \(language).")
        }

        let tempFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("flannel-code-\(UUID().uuidString)", isDirectory: true)
        let scriptURL = tempFolder.appendingPathComponent("snippet.\(runner.fileExtension)")

        do {
            try FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
            try request.code.write(to: scriptURL, atomically: true, encoding: .utf8)
        } catch {
            return unavailable(context, output: "Code execution could not prepare a local script: \(error.localizedDescription)")
        }

        defer { try? FileManager.default.removeItem(at: tempFolder) }

        let result = runProcess(
            executablePath: runner.executablePath,
            arguments: runner.arguments(scriptURL),
            currentDirectory: resolvedWorkingDirectory(from: request.cwd),
            timeout: commandTimeout
        )
        return completed(
            context,
            modifiedFiles: context.tool.canModifyFiles,
            output: formattedProcessOutput(
                title: "Code execution (\(runner.displayName))",
                command: runner.displayName,
                workingDirectory: resolvedWorkingDirectory(from: request.cwd).path,
                result: result
            )
        )
    }

    private func parseTerminalRequest(_ query: String) -> (cwd: String?, command: String) {
        var lines = normalizedLines(from: query)
        let cwd = popPrefixedLine("cwd:", from: &lines)
        return (cwd, lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func parseCodeExecutionRequest(_ query: String) -> (cwd: String?, language: String?, code: String) {
        var lines = normalizedLines(from: query)
        let cwd = popPrefixedLine("cwd:", from: &lines)

        guard let first = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty else {
            return (cwd, nil, "")
        }

        let language: String
        if first.hasPrefix("```") {
            language = String(first.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            lines.removeFirst()
            if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
                lines.removeLast()
            }
        } else if first.lowercased().hasPrefix("language:") {
            language = String(first.dropFirst("language:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            lines.removeFirst()
        } else {
            language = first
            lines.removeFirst()
        }

        return (cwd, language, lines.joined(separator: "\n").trimmingCharacters(in: .newlines))
    }

    private func normalizedLines(from query: String) -> [String] {
        var lines = query
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeFirst()
        }
        return lines
    }

    private func popPrefixedLine(_ prefix: String, from lines: inout [String]) -> String? {
        guard let first = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              first.lowercased().hasPrefix(prefix) else {
            return nil
        }

        lines.removeFirst()
        return String(first.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolvedWorkingDirectory(from rawCWD: String?) -> URL {
        guard let rawCWD, !rawCWD.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return FileManager.default.homeDirectoryForCurrentUser
        }

        let expanded = (rawCWD as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    private func codeRunner(for language: String) -> LocalCodeRunner? {
        switch language {
        case "zsh", "shell", "sh", "bash":
            return LocalCodeRunner(displayName: "zsh", executablePath: "/bin/zsh", fileExtension: "zsh") { [$0.path] }
        case "python", "python3", "py":
            return LocalCodeRunner(displayName: "python3", executablePath: "/usr/bin/env", fileExtension: "py") { ["python3", $0.path] }
        case "javascript", "js", "node":
            return LocalCodeRunner(displayName: "node", executablePath: "/usr/bin/env", fileExtension: "js") { ["node", $0.path] }
        case "swift":
            return LocalCodeRunner(displayName: "swift", executablePath: "/usr/bin/swift", fileExtension: "swift") { [$0.path] }
        default:
            return nil
        }
    }

    private func runProcess(
        executablePath: String,
        arguments: [String],
        currentDirectory: URL,
        timeout: TimeInterval
    ) -> LocalProcessRunResult {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = stdout
        process.standardError = stderr
        process.environment = processEnvironment()

        let startedAt = Date()
        do {
            try process.run()
        } catch {
            return LocalProcessRunResult(
                exitCode: -1,
                stdout: "",
                stderr: error.localizedDescription,
                timedOut: false,
                duration: Date().timeIntervalSince(startedAt)
            )
        }

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        while process.isRunning {
            if Date() >= deadline {
                timedOut = true
                process.terminate()
                break
            }
            Thread.sleep(forTimeInterval: 0.025)
        }

        let stdoutText = cappedString(from: stdout.fileHandleForReading.readDataToEndOfFile())
        let stderrText = cappedString(from: stderr.fileHandleForReading.readDataToEndOfFile())

        return LocalProcessRunResult(
            exitCode: process.terminationStatus,
            stdout: stdoutText,
            stderr: stderrText,
            timedOut: timedOut,
            duration: Date().timeIntervalSince(startedAt)
        )
    }

    private func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["FLANNEL_LOCAL_TOOL"] = "1"
        return environment
    }

    private func cappedString(from data: Data) -> String {
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii)
            ?? ""
        if text.count <= maximumOutputCharacters {
            return text.trimmingCharacters(in: .newlines)
        }

        let prefix = String(text.prefix(maximumOutputCharacters))
        return prefix.trimmingCharacters(in: .newlines) + "\n\n[Output truncated by Flannel]"
    }

    private func formattedProcessOutput(
        title: String,
        command: String,
        workingDirectory: String,
        result: LocalProcessRunResult
    ) -> String {
        var sections = [
            title,
            "Command: \(command)",
            "Working directory: \(workingDirectory)",
            "Exit code: \(result.exitCode)",
            "Duration: \(String(format: "%.2fs", result.duration))"
        ]
        if result.timedOut {
            sections.append("Timed out after \(Int(commandTimeout))s and was terminated.")
        }

        if !result.stdout.isEmpty {
            sections.append("\nstdout\n\(result.stdout)")
        }

        if !result.stderr.isEmpty {
            sections.append("\nstderr\n\(result.stderr)")
        }

        return sections.joined(separator: "\n")
    }
}

private struct LocalProcessRunResult: Sendable, Hashable {
    var exitCode: Int32
    var stdout: String
    var stderr: String
    var timedOut: Bool
    var duration: TimeInterval
}

private struct LocalCodeRunner: Sendable {
    var displayName: String
    var executablePath: String
    var fileExtension: String
    var arguments: @Sendable (URL) -> [String]
}
