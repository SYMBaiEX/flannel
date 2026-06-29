//
//  FlannelStatusChip.swift
//  flannel
//
//  Created by OpenAI Codex on 6/29/26.
//

import SwiftUI

enum FlannelStatusTone {
    case neutral
    case accent
    case success
    case warning
    case danger
    case info
    case custom(Color)

    var color: Color {
        switch self {
        case .neutral:
            .secondary
        case .accent:
            .accentColor
        case .success:
            .green
        case .warning:
            .orange
        case .danger:
            .red
        case .info:
            .blue
        case .custom(let color):
            color
        }
    }
}

enum FlannelStatusChipProminence {
    case subtle
    case tinted
    case glass
}

struct FlannelStatusChip: View {
    var title: String
    var systemImage: String?
    var tone: FlannelStatusTone
    var prominence: FlannelStatusChipProminence

    init(
        _ title: String,
        systemImage: String? = nil,
        tone: FlannelStatusTone = .neutral,
        prominence: FlannelStatusChipProminence = .subtle
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tone = tone
        self.prominence = prominence
    }

    var body: some View {
        chipLabel
            .font(.caption)
            .lineLimit(1)
            .foregroundStyle(tone.color)
            .padding(.horizontal, FlannelSpacing.chipHorizontal)
            .padding(.vertical, FlannelSpacing.chipVertical)
            .modifier(FlannelStatusChipBackground(tone: tone, prominence: prominence))
    }

    @ViewBuilder
    private var chipLabel: some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
        } else {
            Text(title)
        }
    }
}

private struct FlannelStatusChipBackground: ViewModifier {
    var tone: FlannelStatusTone
    var prominence: FlannelStatusChipProminence

    func body(content: Content) -> some View {
        switch prominence {
        case .subtle:
            content
                .background(Material.thin, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(FlannelSystemColor.quietStroke, lineWidth: FlannelSpacing.hairline)
                }
        case .tinted:
            content
                .background(tone.color.opacity(0.13), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(tone.color.opacity(0.24), lineWidth: FlannelSpacing.hairline)
                }
        case .glass:
            content
                .glassEffect(Glass.regular.tint(tone.color.opacity(0.12)), in: Capsule())
        }
    }
}

