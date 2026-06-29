//
//  FlannelMessageBubble.swift
//  flannel
//
//  Created by OpenAI Codex on 6/29/26.
//

import SwiftUI

enum FlannelMessageBubbleRole {
    case user
    case assistant
    case system
    case tool

    var backgroundStyle: AnyShapeStyle {
        switch self {
        case .user:
            AnyShapeStyle(Color.accentColor.opacity(0.14))
        case .assistant:
            AnyShapeStyle(Material.thin)
        case .system:
            AnyShapeStyle(Material.ultraThin)
        case .tool:
            AnyShapeStyle(Color.secondary.opacity(0.10))
        }
    }

    var strokeStyle: AnyShapeStyle {
        switch self {
        case .user:
            AnyShapeStyle(Color.accentColor.opacity(0.26))
        case .assistant, .system:
            AnyShapeStyle(FlannelSystemColor.quietStroke)
        case .tool:
            AnyShapeStyle(Color.secondary.opacity(0.22))
        }
    }
}

private struct FlannelMessageBubbleModifier: ViewModifier {
    var role: FlannelMessageBubbleRole
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .padding(.horizontal, FlannelSpacing.messageHorizontal)
            .padding(.vertical, FlannelSpacing.messageVertical)
            .background(role.backgroundStyle, in: shape)
            .overlay {
                shape.strokeBorder(role.strokeStyle, lineWidth: FlannelSpacing.hairline)
            }
    }
}

extension View {
    func flannelMessageBubble(
        role: FlannelMessageBubbleRole = .assistant,
        cornerRadius: CGFloat = FlannelRadius.lg
    ) -> some View {
        modifier(FlannelMessageBubbleModifier(role: role, cornerRadius: cornerRadius))
    }
}

