import SwiftUI

/// Glass surface: the system Liquid Glass material on iOS 26 (when built with the
/// iOS 26 SDK), a translucent material with a hairline highlight on iOS 17/18.
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
            .shadow(color: .black.opacity(0.06), radius: 14, y: 5)
    }
}

/// Content card. Classic: opaque grouped-background card. Liquid Glass: glass surface.
/// Both themes share every page; only this surface (and the page background) differ.
struct FinanceCard: ViewModifier {
    var padding: CGFloat = DS.Spacing.l
    var radius: CGFloat = DS.Radius.card

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let padded = content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
        switch AppSettings.theme {
        case .classic:
            padded.background(DS.Colors.card, in: shape)
        case .liquidGlass:
            padded.modifier(GlassSurface(shape: shape))
        }
    }
}

/// Page background for scrolling pages.
struct PageBackground: View {
    var body: some View {
        switch AppSettings.theme {
        case .classic:
            DS.Colors.background.ignoresSafeArea()
        case .liquidGlass:
            ZStack {
                DS.Colors.background
                LinearGradient(
                    colors: [DS.Colors.accent.opacity(0.14), .clear, DS.Colors.accent.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .ignoresSafeArea()
        }
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
        modifier(FinanceCard(padding: padding, radius: radius))
    }

    /// Background for List/Form pages in either theme.
    func pageBackground() -> some View {
        scrollContentBackground(.hidden).background(PageBackground())
    }
}
