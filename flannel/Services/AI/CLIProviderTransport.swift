//
//  CLIProviderTransport.swift
//  flannel
//
//  Created by OpenAI Codex on 6/28/26.
//

import Foundation

nonisolated struct CLIProviderPreparedCommand: Equatable, Sendable {
    var providerDisplayName: String
    var executableURL: URL
    var arguments: [String]
    var stdinText: String?
    var timeout: Duration
    var outputFormat: CLIProviderOutputFormat
}

nonisolated struct CLIProviderOutputDecoder: Sendable {
    var providerDisplayName: String
    var format: CLIProviderOutputFormat
    private var pendingText = ""
    private var hasYieldedText = false

    nonisolated init(providerDisplayName: String, format: CLIProviderOutputFormat) {
        self.providerDisplayName = providerDisplayName
        self.format = format
    }

    mutating func decode(_ chunk: String) throws -> [String] {
        try decodeEvents(chunk).compactMap { event in
            guard case .text(let text) = event else { return nil }
            return text
        }
    }

    mutating func decodeEvents(_ chunk: String) throws -> [ChatStreamingEvent] {
        switch format {
        case .plainText:
            return chunk.isEmpty ? [] : [.text(chunk)]

        case .codexJSONLines, .claudeStreamJSON:
            pendingText += chunk
            return try drainCompleteLines()

        case .claudeJSON:
            pendingText += chunk
            return []
        }
    }

    mutating func finish() throws -> [String] {
        try finishEvents().compactMap { event in
            guard case .text(let text) = event else { return nil }
            return text
        }
    }

    mutating func finishEvents() throws -> [ChatStreamingEvent] {
        switch format {
        case .plainText:
            return []

        case .codexJSONLines, .claudeStreamJSON:
            let line = pendingText
            pendingText = ""
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return []
            }
            return try decodeStructuredLine(line)

        case .claudeJSON:
            let payload = pendingText.trimmingCharacters(in: .whitespacesAndNewlines)
            pendingText = ""
            guard !payload.isEmpty else { return [] }
            let object = try jsonObject(from: payload)
            let fragments = Self.claudeTextFragments(from: object)
            hasYieldedText = hasYieldedText || !fragments.isEmpty
            return Self.events(from: fragments, usage: Self.usage(from: object))
        }
    }

    private mutating func drainCompleteLines() throws -> [ChatStreamingEvent] {
        var output: [ChatStreamingEvent] = []

        while let newlineRange = pendingText.range(of: "\n") {
            let line = String(pendingText[..<newlineRange.lowerBound])
            pendingText.removeSubrange(..<newlineRange.upperBound)
            output.append(contentsOf: try decodeStructuredLine(line))
        }

        return output
    }

    private mutating func decodeStructuredLine(_ line: String) throws -> [ChatStreamingEvent] {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty else { return [] }
        let object = try jsonObject(from: trimmedLine)
        let fragments: [String]

        switch format {
        case .plainText:
            fragments = [line]
        case .codexJSONLines:
            fragments = Self.codexTextFragments(from: object)
        case .claudeJSON, .claudeStreamJSON:
            fragments = Self.claudeTextFragments(from: object, hasYieldedText: hasYieldedText)
        }

        hasYieldedText = hasYieldedText || !fragments.isEmpty
        return Self.events(from: fragments, usage: Self.usage(from: object))
    }

    private func jsonObject(from text: String) throws -> Any {
        guard let data = text.data(using: .utf8) else {
            throw CLIProviderTransportError.invalidUTF8Output(providerDisplayName)
        }

        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw CLIProviderTransportError.invalidStructuredOutput(
                providerDisplayName,
                detail: error.localizedDescription
            )
        }
    }

    private static func codexTextFragments(from object: Any) -> [String] {
        guard let event = object as? [String: Any] else { return [] }
        let message = (event["msg"] as? [String: Any]) ?? event
        let type = stringValue(message["type"]) ?? ""

        if type == "item.completed",
           let item = message["item"] as? [String: Any] {
            guard stringValue(item["role"]) == "assistant" || stringValue(item["type"]) == "message" else {
                return []
            }
            return textFragments(from: item["content"])
        }

        if type == "agent_message" || type == "assistant_message" {
            return textFragments(from: message["message"]) + textFragments(from: message["content"])
        }

        if stringValue(message["role"]) == "assistant" {
            return textFragments(from: message["content"])
                + textFragments(from: message["message"])
                + textFragments(from: message["text"])
        }

        return []
    }

    private static func claudeTextFragments(from object: Any, hasYieldedText: Bool = false) -> [String] {
        guard let event = object as? [String: Any] else {
            return textFragments(from: object)
        }

        let type = stringValue(event["type"]) ?? ""

        if type == "content_block_delta",
           let delta = event["delta"] as? [String: Any] {
            return textFragments(from: delta["text"])
        }

        if type == "assistant",
           let message = event["message"] {
            return textFragments(from: message)
        }

        if type == "result" {
            return hasYieldedText ? [] : textFragments(from: event["result"])
        }

        if let result = event["result"],
           !hasYieldedText {
            return textFragments(from: result)
        }

        if stringValue(event["role"]) == "assistant" {
            return textFragments(from: event["content"])
                + textFragments(from: event["message"])
                + textFragments(from: event["text"])
        }

        return []
    }

    private static func events(from fragments: [String], usage: ChatStreamUsage?) -> [ChatStreamingEvent] {
        var events = fragments
            .filter { !$0.isEmpty }
            .map(ChatStreamingEvent.text)
        if let usage {
            events.append(.usage(usage))
        }
        return events
    }

    private static func usage(from object: Any) -> ChatStreamUsage? {
        if let usageObject = object as? [String: Any],
           let usage = usage(from: usageObject["usage"]) {
            return usage
        }

        guard let event = object as? [String: Any] else {
            return nil
        }

        if let usage = usage(from: event["msg"]) {
            return usage
        }
        if let usage = usage(from: event["message"]) {
            return usage
        }
        if let usage = usage(from: event["response"]) {
            return usage
        }
        if let usage = usage(from: event["item"]) {
            return usage
        }
        return usage(fromTokenFields: event)
    }

    private static func usage(from value: Any?) -> ChatStreamUsage? {
        guard let value else { return nil }

        if let object = value as? [String: Any] {
            if let nested = object["usage"],
               let usage = usage(from: nested) {
                return usage
            }
            return usage(fromTokenFields: object)
        }

        return nil
    }

    private static func usage(fromTokenFields object: [String: Any]) -> ChatStreamUsage? {
        let inputTokens = intValue(
            object["input_tokens"] ?? object["inputTokens"] ?? object["prompt_tokens"] ?? object["promptTokens"]
        )
        let outputTokens = intValue(
            object["output_tokens"] ?? object["outputTokens"] ?? object["completion_tokens"] ?? object["completionTokens"]
        )
        let explicitTotal = intValue(object["total_tokens"] ?? object["totalTokens"])
        let totalTokens: Int?
        if let explicitTotal {
            totalTokens = explicitTotal
        } else if let inputTokens, let outputTokens {
            totalTokens = inputTokens + outputTokens
        } else {
            totalTokens = nil
        }
        let latencyMilliseconds = intValue(
            object["latency_milliseconds"] ?? object["latencyMilliseconds"] ?? object["latency_ms"] ?? object["duration_ms"]
        )

        guard inputTokens != nil || outputTokens != nil || totalTokens != nil || latencyMilliseconds != nil else {
            return nil
        }

        return ChatStreamUsage(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            latencyMilliseconds: latencyMilliseconds
        )
    }

    private static func textFragments(from value: Any?) -> [String] {
        guard let value else { return [] }

        if let string = value as? String {
            return string.isEmpty ? [] : [string]
        }

        if let array = value as? [Any] {
            return array.flatMap { textFragments(from: $0) }
        }

        guard let object = value as? [String: Any] else {
            return []
        }

        if let text = stringValue(object["text"]) {
            return text.isEmpty ? [] : [text]
        }

        if let content = object["content"] {
            return textFragments(from: content)
        }

        if let message = object["message"] {
            return textFragments(from: message)
        }

        if let delta = object["delta"] {
            return textFragments(from: delta)
        }

        if let result = object["result"] {
            return textFragments(from: result)
        }

        return []
    }

    private static func stringValue(_ value: Any?) -> String? {
        value as? String
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let int64 as Int64:
            return Int(int64)
        case let double as Double:
            return Int(double)
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }
}

nonisolated struct CLIProviderTransport: Sendable {
    typealias ExecutableResolver = @Sendable (String) -> URL?
    typealias CommandExecutor = @Sendable (CLIProviderPreparedCommand) -> AsyncThrowingStream<String, Error>
    typealias EventCommandExecutor = @Sendable (CLIProviderPreparedCommand) -> AsyncThrowingStream<ChatStreamingEvent, Error>

    var commandBuilder: CLIProviderCommandBuilder
    var resolveExecutable: ExecutableResolver
    var executeCommand: CommandExecutor
    var executeEvents: EventCommandExecutor

    nonisolated init(
        commandBuilder: CLIProviderCommandBuilder = CLIProviderCommandBuilder(),
        resolveExecutable: @escaping ExecutableResolver = { executable in
            Self.resolveExecutable(named: executable)
        },
        executeCommand: CommandExecutor? = nil,
        executeEvents: EventCommandExecutor? = nil
    ) {
        let resolvedTextExecutor: CommandExecutor = executeCommand ?? { command in
            Self.liveExecuteCommand(command)
        }
        self.commandBuilder = commandBuilder
        self.resolveExecutable = resolveExecutable
        self.executeCommand = resolvedTextExecutor
        if let executeEvents {
            self.executeEvents = executeEvents
        } else if let executeCommand {
            self.executeEvents = { command in
                Self.events(fromTextStream: executeCommand(command))
            }
        } else {
            self.executeEvents = { command in
                Self.liveExecuteCommandEvents(command)
            }
        }
    }

    nonisolated func streamText(for request: ChatStreamingRequest) -> AsyncThrowingStream<String, Error> {
        do {
            let preparedCommand = try makePreparedCommand(for: request)
            return executeCommand(preparedCommand)
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }
    }

    nonisolated func streamEvents(for request: ChatStreamingRequest) -> AsyncThrowingStream<ChatStreamingEvent, Error> {
        do {
            let preparedCommand = try makePreparedCommand(for: request)
            return executeEvents(preparedCommand)
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }
    }

    nonisolated func streamText(for commandSpec: CLIProviderCommandSpec) -> AsyncThrowingStream<String, Error> {
        do {
            let preparedCommand = try makePreparedCommand(for: commandSpec)
            return executeCommand(preparedCommand)
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }
    }

    nonisolated func streamEvents(for commandSpec: CLIProviderCommandSpec) -> AsyncThrowingStream<ChatStreamingEvent, Error> {
        do {
            let preparedCommand = try makePreparedCommand(for: commandSpec)
            return executeEvents(preparedCommand)
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }
    }

    nonisolated func makePreparedCommand(for request: ChatStreamingRequest) throws -> CLIProviderPreparedCommand {
        let commandSpec = try commandBuilder.makeCommandSpec(for: request)
        return try makePreparedCommand(for: commandSpec)
    }

    nonisolated func makePreparedCommand(for commandSpec: CLIProviderCommandSpec) throws -> CLIProviderPreparedCommand {
        guard let executableURL = resolveExecutable(commandSpec.executable) else {
            throw CLIProviderTransportError.missingExecutable(commandSpec.executable)
        }

        return CLIProviderPreparedCommand(
            providerDisplayName: commandSpec.providerDisplayName,
            executableURL: executableURL,
            arguments: commandSpec.arguments,
            stdinText: commandSpec.stdinText,
            timeout: commandSpec.timeout,
            outputFormat: commandSpec.outputFormat
        )
    }

    nonisolated static func resolveExecutable(named rawValue: String) -> URL? {
        let executable = (rawValue as NSString).expandingTildeInPath
        let fileManager = FileManager.default

        if executable.contains("/") {
            let url = URL(fileURLWithPath: executable)
            return fileManager.isExecutableFile(atPath: url.path) ? url : nil
        }

        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        for pathEntry in pathEntries where !pathEntry.isEmpty {
            let candidate = URL(fileURLWithPath: pathEntry).appendingPathComponent(executable)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }

    nonisolated static func liveExecuteCommand(_ command: CLIProviderPreparedCommand) -> AsyncThrowingStream<String, Error> {
        events(fromEventStream: liveExecuteCommandEvents(command))
    }

    nonisolated static func liveExecuteCommandEvents(
        _ command: CLIProviderPreparedCommand
    ) -> AsyncThrowingStream<ChatStreamingEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(command, continuation: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CLIProviderTransportError.cancelled(command.providerDisplayName))
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    nonisolated private static func events(
        fromTextStream stream: AsyncThrowingStream<String, Error>
    ) -> AsyncThrowingStream<ChatStreamingEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await text in stream where !text.isEmpty {
                        continuation.yield(.text(text))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    nonisolated private static func events(
        fromEventStream stream: AsyncThrowingStream<ChatStreamingEvent, Error>
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in stream {
                        guard case .text(let text) = event,
                              !text.isEmpty else { continue }
                        continuation.yield(text)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    nonisolated private static func run(
        _ command: CLIProviderPreparedCommand,
        continuation: AsyncThrowingStream<ChatStreamingEvent, Error>.Continuation
    ) async throws {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if command.stdinText != nil {
            process.standardInput = Pipe()
        }

        do {
            try process.run()
        } catch {
            throw CLIProviderTransportError.failedToStart(error.localizedDescription)
        }

        if let stdinPipe = process.standardInput as? Pipe,
           let stdinText = command.stdinText {
            let stdinData = Data(stdinText.utf8)
            stdinPipe.fileHandleForWriting.write(stdinData)
            try? stdinPipe.fileHandleForWriting.close()
        }

        let stdoutTask = Task {
            try await stream(
                handle: stdoutPipe.fileHandleForReading,
                provider: command.providerDisplayName,
                outputFormat: command.outputFormat,
                continuation: continuation
            )
        }
        let stderrTask = Task {
            try await collect(handle: stderrPipe.fileHandleForReading)
        }

        do {
            let status = try await waitForExit(process, provider: command.providerDisplayName, timeout: command.timeout)
            try await stdoutTask.value
            let stderrData = try await stderrTask.value

            guard status == 0 else {
                let stderrText = String(data: stderrData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw CLIProviderTransportError.processExitedNonZero(
                    command.providerDisplayName,
                    code: status,
                    stderr: stderrText
                )
            }
        } catch {
            stdoutTask.cancel()
            stderrTask.cancel()
            terminate(process)
            throw error
        }
    }

    nonisolated private static func stream(
        handle: FileHandle,
        provider: String,
        outputFormat: CLIProviderOutputFormat,
        continuation: AsyncThrowingStream<ChatStreamingEvent, Error>.Continuation
    ) async throws {
        var buffer = Data()
        var decoder = CLIProviderOutputDecoder(providerDisplayName: provider, format: outputFormat)

        for try await byte in handle.bytes {
            try Task.checkCancellation()
            buffer.append(byte)

            if byte == 0x0A || buffer.count >= 1024 {
                try flush(&buffer, provider: provider, decoder: &decoder, continuation: continuation)
            }
        }

        try flush(&buffer, provider: provider, decoder: &decoder, continuation: continuation)
        for decodedEvent in try decoder.finishEvents() {
            continuation.yield(decodedEvent)
        }
    }

    nonisolated private static func collect(handle: FileHandle) async throws -> Data {
        var data = Data()
        for try await byte in handle.bytes {
            try Task.checkCancellation()
            data.append(byte)
        }
        return data
    }

    nonisolated private static func flush(
        _ buffer: inout Data,
        provider: String,
        decoder: inout CLIProviderOutputDecoder,
        continuation: AsyncThrowingStream<ChatStreamingEvent, Error>.Continuation
    ) throws {
        guard !buffer.isEmpty else { return }
        guard let chunk = String(data: buffer, encoding: .utf8) else {
            throw CLIProviderTransportError.invalidUTF8Output(provider)
        }
        for decodedEvent in try decoder.decodeEvents(chunk) {
            continuation.yield(decodedEvent)
        }
        buffer.removeAll(keepingCapacity: true)
    }

    nonisolated private static func waitForExit(
        _ process: Process,
        provider: String,
        timeout: Duration
    ) async throws -> Int32 {
        let seconds = max(1, Int(timeout.components.seconds))

        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Int32.self) { group in
                group.addTask {
                    process.waitUntilExit()
                    return process.terminationStatus
                }

                group.addTask {
                    try await Task.sleep(for: timeout)
                    terminate(process)
                    throw CLIProviderTransportError.processTimedOut(provider, seconds: seconds)
                }

                do {
                    let result = try await group.next()
                    group.cancelAll()
                    return result ?? process.terminationStatus
                } catch {
                    group.cancelAll()
                    throw error
                }
            }
        } onCancel: {
            terminate(process)
        }
    }

    nonisolated private static func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.interrupt()
        if process.isRunning {
            process.terminate()
        }
    }
}
