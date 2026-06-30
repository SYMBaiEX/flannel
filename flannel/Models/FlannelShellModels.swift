//
//  FlannelShellModels.swift
//  flannel
//
//  Created by OpenAI Codex on 6/29/26.
//

import CoreGraphics
import Foundation

nonisolated enum FlannelSidebarSurface: String, Hashable, Sendable {
    case conversation
    case settings

    var showsConversationFooter: Bool {
        self == .conversation
    }

    var showsInspectorColumn: Bool {
        self == .conversation
    }

    var columnWidth: FlannelSidebarColumnWidth {
        switch self {
        case .conversation:
            FlannelSidebarColumnWidth(min: 248, ideal: 280, max: 328)
        case .settings:
            FlannelSidebarColumnWidth(min: 220, ideal: 248, max: 292)
        }
    }
}

nonisolated enum FlannelExitCommandIntent: Hashable, Sendable {
    case exitSettings
    case collapseArtifacts
    case none

    static func resolve(
        sidebarSurface: FlannelSidebarSurface,
        isInspectorVisible: Bool
    ) -> FlannelExitCommandIntent {
        if sidebarSurface == .settings {
            return .exitSettings
        }
        if isInspectorVisible {
            return .collapseArtifacts
        }
        return .none
    }
}

nonisolated struct FlannelSidebarColumnWidth: Hashable, Sendable {
    var min: CGFloat
    var ideal: CGFloat
    var max: CGFloat
}

nonisolated enum FlannelTranscriptFollowPolicy {
    static let defaultBottomThreshold: CGFloat = 88

    static func isPinnedToBottom(
        bottomDistance: CGFloat,
        threshold: CGFloat = defaultBottomThreshold
    ) -> Bool {
        bottomDistance <= threshold
    }
}

nonisolated enum FlannelInspectorSection: String, CaseIterable, Hashable, Identifiable, Sendable {
    case chatDetail
    case sources
    case compare
    case tools

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chatDetail:
            "Details"
        case .sources:
            "Sources"
        case .compare:
            "Compare"
        case .tools:
            "Tool Traces"
        }
    }

    var icon: String {
        switch self {
        case .chatDetail:
            "bubble.left.and.text.bubble.right"
        case .sources:
            "books.vertical"
        case .compare:
            "rectangle.split.3x1"
        case .tools:
            "wrench.and.screwdriver"
        }
    }

    static func defaultSection(
        hasCompareArtifacts: Bool,
        hasSourceArtifacts: Bool,
        hasToolArtifacts: Bool
    ) -> FlannelInspectorSection {
        if hasSourceArtifacts {
            return .sources
        }
        if hasCompareArtifacts {
            return .compare
        }
        if hasToolArtifacts {
            return .tools
        }
        return .chatDetail
    }

    static func availableSections(
        hasCompareArtifacts: Bool,
        hasSourceArtifacts: Bool,
        hasToolArtifacts: Bool
    ) -> [FlannelInspectorSection] {
        allCases
    }
}
