//
//  KnowledgeSourceWatchService.swift
//  flannel
//
//  Created by OpenAI Codex on 6/29/26.
//

import CoreServices
import Foundation

struct KnowledgeSourceWatchDescriptor: Hashable, Identifiable, Sendable {
    var sourceID: UUID
    var kind: KnowledgeSourceKind
    var title: String
    var rootPath: String

    var id: UUID { sourceID }
}

final class KnowledgeSourceWatchService {
    typealias ChangeHandler = @Sendable (Set<UUID>) -> Void

    private struct SendableChangeHandler: @unchecked Sendable {
        let run: @Sendable (Set<UUID>) -> Void

        init(_ run: @escaping @Sendable (Set<UUID>) -> Void) {
            self.run = run
        }
    }

    private final class CallbackBox {
        weak var owner: KnowledgeSourceWatchService?
        let descriptor: KnowledgeSourceWatchDescriptor

        init(owner: KnowledgeSourceWatchService, descriptor: KnowledgeSourceWatchDescriptor) {
            self.owner = owner
            self.descriptor = descriptor
        }
    }

    private let queue = DispatchQueue(label: "flannel.knowledge-source-watch", qos: .utility)
    private let lock = NSLock()
    private var descriptors: Set<KnowledgeSourceWatchDescriptor> = []
    private var streams: [UUID: FSEventStreamRef] = [:]
    private var callbackBoxes: [UUID: CallbackBox] = [:]
    private var pendingSourceIDs: Set<UUID> = []
    private var pendingWorkItem: DispatchWorkItem?
    private var changeHandler: SendableChangeHandler?
    private let debounceNanoseconds: UInt64

    init(debounceNanoseconds: UInt64 = 900_000_000) {
        self.debounceNanoseconds = debounceNanoseconds
    }

    deinit {
        stop()
    }

    var watchedSourceIDs: Set<UUID> {
        lock.withLock {
            Set(streams.keys)
        }
    }

    func update(
        sources: [KnowledgeSource],
        changeHandler: @escaping ChangeHandler
    ) {
        let nextDescriptors = Set(Self.watchDescriptors(for: sources))

        lock.withLock {
            self.changeHandler = SendableChangeHandler(changeHandler)
            guard nextDescriptors != descriptors else { return }
            stopLocked()
            descriptors = nextDescriptors
            for descriptor in nextDescriptors {
                startLocked(descriptor)
            }
        }
    }

    func stop() {
        lock.withLock {
            stopLocked()
            descriptors.removeAll()
            changeHandler = nil
        }
    }

    static func watchDescriptors(
        for sources: [KnowledgeSource],
        fileManager: FileManager = .default
    ) -> [KnowledgeSourceWatchDescriptor] {
        sources
            .compactMap { descriptor(for: $0, fileManager: fileManager) }
            .sorted { lhs, rhs in
                lhs.rootPath.localizedStandardCompare(rhs.rootPath) == .orderedAscending
            }
    }

    private static func descriptor(
        for source: KnowledgeSource,
        fileManager: FileManager
    ) -> KnowledgeSourceWatchDescriptor? {
        guard source.isWatched,
              source.kind.supportsFileSystemWatching else {
            return nil
        }

        let expandedPath = (source.location as NSString).expandingTildeInPath
        let rootURL = URL(fileURLWithPath: expandedPath).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        return KnowledgeSourceWatchDescriptor(
            sourceID: source.id,
            kind: source.kind,
            title: source.title,
            rootPath: rootURL.path
        )
    }

    private func startLocked(_ descriptor: KnowledgeSourceWatchDescriptor) {
        let box = CallbackBox(owner: self, descriptor: descriptor)
        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(box).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagWatchRoot
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.eventCallback,
            &context,
            [descriptor.rootPath] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.35,
            flags
        ) else {
            return
        }

        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return
        }

        streams[descriptor.sourceID] = stream
        callbackBoxes[descriptor.sourceID] = box
    }

    private func stopLocked() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        pendingSourceIDs.removeAll()
        for stream in streams.values {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        streams.removeAll()
        callbackBoxes.removeAll()
    }

    private func recordChange(for sourceID: UUID) {
        var workItemToSchedule: DispatchWorkItem?
        let delay = DispatchTimeInterval.nanoseconds(Int(debounceNanoseconds))

        lock.withLock {
            pendingSourceIDs.insert(sourceID)
            pendingWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.flushPendingChanges()
            }
            pendingWorkItem = workItem
            workItemToSchedule = workItem
        }

        if let workItemToSchedule {
            queue.asyncAfter(deadline: .now() + delay, execute: workItemToSchedule)
        }
    }

    private func flushPendingChanges() {
        let payload: (sourceIDs: Set<UUID>, handler: SendableChangeHandler?) = lock.withLock {
            let sourceIDs = pendingSourceIDs
            pendingSourceIDs.removeAll()
            pendingWorkItem = nil
            return (sourceIDs, changeHandler)
        }

        guard !payload.sourceIDs.isEmpty else { return }
        payload.handler?.run(payload.sourceIDs)
    }

    private static let eventCallback: FSEventStreamCallback = { _, info, _, _, _, _ in
        guard let info else { return }
        let box = Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue()
        box.owner?.recordChange(for: box.descriptor.sourceID)
    }
}

extension KnowledgeSourceKind {
    var supportsFileSystemWatching: Bool {
        switch self {
        case .folder, .codeRepository:
            true
        case .file, .webPage, .chatHistory, .workspaceNotes:
            false
        }
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
