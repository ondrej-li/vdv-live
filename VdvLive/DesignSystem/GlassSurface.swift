import SwiftUI

/// The translucent surface the map's floating chrome is drawn on.
///
/// The app requires iOS 26, so this is Liquid Glass everywhere: one modifier, so the
/// bar, the search circle and the map's own controls cannot drift apart.
struct GlassSurface: ViewModifier {
    /// What the surface is cut to.
    enum Outline {
        case capsule
        case circle
        case rounded(CGFloat)
    }

    var outline: Outline = .rounded(22)

    func body(content: Content) -> some View {
        content.glassEffect(.regular, in: shape)
    }

    private var shape: AnyShape {
        switch outline {
        case .capsule:
            AnyShape(Capsule())
        case .circle:
            AnyShape(Circle())
        case .rounded(let radius):
            AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}

extension View {
    /// Draws the view on the app's glass, cut to `outline`.
    func glassSurface(_ outline: GlassSurface.Outline = .rounded(22)) -> some View {
        modifier(GlassSurface(outline: outline))
    }
}
