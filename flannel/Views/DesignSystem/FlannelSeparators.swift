//
//  FlannelSeparators.swift
//  flannel
//
//  Created by OpenAI Codex on 6/29/26.
//

import SwiftUI

struct FlannelSeparator: View {
    enum Orientation {
        case horizontal
        case vertical
    }

    var orientation: Orientation = .horizontal
    var opacity: Double = 1

    var body: some View {
        switch orientation {
        case .horizontal:
            Rectangle()
                .fill(FlannelSystemColor.hairline.opacity(opacity))
                .frame(height: FlannelSpacing.hairline)
        case .vertical:
            Rectangle()
                .fill(FlannelSystemColor.hairline.opacity(opacity))
                .frame(width: FlannelSpacing.hairline)
        }
    }
}

private struct FlannelSeparatorModifier: ViewModifier {
    var edge: Edge
    var inset: CGFloat
    var opacity: Double

    func body(content: Content) -> some View {
        content.overlay(alignment: edge.flannelSeparatorAlignment) {
            FlannelSeparator(orientation: edge.flannelSeparatorOrientation, opacity: opacity)
                .padding(edge.flannelSeparatorInsetEdges, inset)
        }
    }
}

extension View {
    func flannelSeparator(edge: Edge = .bottom, inset: CGFloat = 0, opacity: Double = 1) -> some View {
        modifier(FlannelSeparatorModifier(edge: edge, inset: inset, opacity: opacity))
    }
}

private extension Edge {
    var flannelSeparatorAlignment: Alignment {
        switch self {
        case .top:
            .top
        case .leading:
            .leading
        case .bottom:
            .bottom
        case .trailing:
            .trailing
        }
    }

    var flannelSeparatorOrientation: FlannelSeparator.Orientation {
        switch self {
        case .top, .bottom:
            .horizontal
        case .leading, .trailing:
            .vertical
        }
    }

    var flannelSeparatorInsetEdges: Edge.Set {
        switch self {
        case .top, .bottom:
            .horizontal
        case .leading, .trailing:
            .vertical
        }
    }
}

