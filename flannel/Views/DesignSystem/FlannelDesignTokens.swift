//
//  FlannelDesignTokens.swift
//  flannel
//
//  Created by OpenAI Codex on 6/29/26.
//

import AppKit
import SwiftUI

enum FlannelSpacing {
    static let hairline: CGFloat = 0.5
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let xxl: CGFloat = 20
    static let section: CGFloat = 24
    static let panel: CGFloat = 32

    static let chipHorizontal: CGFloat = 8
    static let chipVertical: CGFloat = 5
    static let rowVertical: CGFloat = 7
    static let paneInset: CGFloat = 16
    static let messageHorizontal: CGFloat = 13
    static let messageVertical: CGFloat = 10
}

enum FlannelRadius {
    static let xs: CGFloat = 5
    static let sm: CGFloat = 7
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
}

enum FlannelSystemColor {
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let contentBackground = Color(nsColor: .controlBackgroundColor)
    static let separator = Color(nsColor: .separatorColor)
    static let hairline = Color(nsColor: .separatorColor).opacity(0.55)
    static let quietStroke = Color(nsColor: .separatorColor).opacity(0.42)
}

