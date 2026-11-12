import SwiftUI

/// Lightweight glass surface. Uses the system Liquid Glass material on iOS 26
/// when built with the iOS 26 SDK, and a translucent material with a soft
/// highlight stroke on iOS 17/18.
struct GlassSurface<S: InsettableShape>: ViewModifier {
    var shape: S
    var interactive: Bool = false

    func body(content: Content) -> some View {
        styled(content)
    }

    #if compiler(>=6.2)
    @ViewBuilder
    private func styled(_ content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            fallback(content)
        }
    }
    #else
    @ViewBuilder
    private func styled(_ content: Content) -> some View {
        fallback(content)
    }
    #endif

    private func fallback(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(DS.Colors.glassStroke, lineWidth: 0.6))
            .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
    }
}

/// Plain card surface used for content blocks (no blur — cheaper and calmer).
struct CardSurface: ViewModifier {
    var padding: CGFloat = DS.Spacing.l
    var radius: CGFloat = DS.Radius.card

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Colors.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func glass<S: InsettableShape>(in shape: S, interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: shape, interactive: interactive))
    }

    func glassCapsule(interactive: Bool = false) -> some View {
        glass(in: Capsule(style: .continuous), interactive: interactive)
    }

    func card(padding: CGFloat = DS.Spacing.l, radius: CGFloat = DS.Radius.card) -> some View {
        modifier(CardSurface(padding: padding, radius: radius))
    }
}
