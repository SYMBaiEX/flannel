//
//  FlannelShellModels.swift
//  flannel
//
//  Created by OpenAI Codex on 6/29/26.
//

import CoreGraphics
import Foundation

enum FlannelSidebarSurface: String, Hashable, Sendable {
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

struct FlannelSidebarColumnWidth: Hashable, Sendable {
    var min: CGFloat
    var ideal: CGFloat
    var max: CGFloat
}
