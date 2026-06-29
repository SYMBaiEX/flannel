//
//  FlannelSurfaces.swift
//  flannel
//
//  Created by OpenAI Codex on 6/29/26.
//

import SwiftUI

enum FlannelBackgroundSurface {
    case window
    case content
    case material(Material = .thin)

    var style: AnyShapeStyle {
        switch self {
        case .window:
            AnyShapeStyle(FlannelSystemColor.windowBackground)
        case .content:
            AnyShapeStyle(FlannelSystemColor.contentBackground)
        case .material(let material):
            AnyShapeStyle(material)
        }
    }
}

enum FlannelPaneSurface {
    case subtle
    case regular
    case prominent

    var material: Material {
        switch self {
        case .subtle:
            .ultraThin
        case .regular:
            .thin
        case .prominent:
            .regular
        }
    }

    var strokeOpacity: Double {
        switch self {
        case .subtle:
            0.28
        case .regular:
            0.42
        case .prominent:
            0.58
        }
    }
}

enum FlannelGlassSurface {
    case regular
    case clear

    var glass: Glass {
        switch self {
        case .regular:
            .regular
        case .clear:
            .clear
        }
    }
}

struct FlannelGlassGroup<Content: View>: View {
    var spacing: CGFloat?
    private let content: Content

    init(spacing: CGFloat? = FlannelSpacing.md, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content
        }
    }
}

private struct FlannelBackgroundSurfaceModifier: ViewModifier {
    var surface: FlannelBackgroundSurface

    func body(content: Content) -> some View {
        content.background(surface.style)
    }
}

private struct FlannelPaneSurfaceModifier: ViewModifier {
    var surface: FlannelPaneSurface
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background(surface.material, in: shape)
            .overlay {
                shape.strokeBorder(
                    FlannelSystemColor.separator.opacity(surface.strokeOpacity),
                    lineWidth: FlannelSpacing.hairline
                )
            }
    }
}

private struct FlannelFloatingDockSurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color?

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .glassEffect(.regular.tint(tint).interactive(true), in: shape)
            .overlay {
                shape.strokeBorder(
                    FlannelSystemColor.separator.opacity(0.22),
                    lineWidth: FlannelSpacing.hairline
                )
            }
            .shadow(color: .black.opacity(0.12), radius: 22, x: 0, y: 14)
            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 1)
    }
}

extension View {
    func flannelBackgroundSurface(_ surface: FlannelBackgroundSurface = .window) -> some View {
        modifier(FlannelBackgroundSurfaceModifier(surface: surface))
    }

    func flannelPaneSurface(
        _ surface: FlannelPaneSurface = .regular,
        cornerRadius: CGFloat = FlannelRadius.lg
    ) -> some View {
        modifier(FlannelPaneSurfaceModifier(surface: surface, cornerRadius: cornerRadius))
    }

    func flannelGlassSurface(
        _ surface: FlannelGlassSurface = .regular,
        tint: Color? = nil,
        interactive: Bool = false,
        cornerRadius: CGFloat = FlannelRadius.lg
    ) -> some View {
        glassEffect(
            surface.glass.tint(tint).interactive(interactive),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }

    func flannelGlassCapsule(
        _ surface: FlannelGlassSurface = .regular,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        glassEffect(surface.glass.tint(tint).interactive(interactive), in: Capsule())
    }

    func flannelFloatingDockSurface(
        cornerRadius: CGFloat = 24,
        tint: Color? = nil
    ) -> some View {
        modifier(FlannelFloatingDockSurfaceModifier(cornerRadius: cornerRadius, tint: tint))
    }
}
