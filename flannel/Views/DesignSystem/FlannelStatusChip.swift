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

    var isNeutral: Bool {
        if case .neutral = self {
            true
        } else {
            false
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
        let capsule = Capsule()

        content
            .flannelGlassCapsule(
                prominence.glassSurface,
                tint: prominence.tintColor(for: tone)
            )
            .overlay {
                capsule.strokeBorder(
                    prominence.strokeStyle(for: tone),
                    lineWidth: FlannelSpacing.hairline
                )
            }
    }
}

private extension FlannelStatusChipProminence {
    var glassSurface: FlannelGlassSurface {
        switch self {
        case .subtle:
            .clear
        case .tinted, .glass:
            .regular
        }
    }

    func tintColor(for tone: FlannelStatusTone) -> Color? {
        switch self {
        case .subtle:
            tone.isNeutral ? nil : tone.color.opacity(0.08)
        case .tinted:
            tone.color.opacity(0.14)
        case .glass:
            tone.color.opacity(0.20)
        }
    }

    func strokeStyle(for tone: FlannelStatusTone) -> AnyShapeStyle {
        switch self {
        case .subtle:
            if tone.isNeutral {
                AnyShapeStyle(FlannelSystemColor.quietStroke)
            } else {
                AnyShapeStyle(tone.color.opacity(0.18))
            }
        case .tinted:
            AnyShapeStyle(tone.color.opacity(0.24))
        case .glass:
            AnyShapeStyle(tone.color.opacity(0.30))
        }
    }
}
