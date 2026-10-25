import SwiftUI

/// The translucent surface the map's floating chrome is drawn on.
///
/// iOS 26 draws real Liquid Glass; earlier systems get the frosted material that
/// preceded it, which reads the same at this size and keeps the deployment target
/// at iOS 18. One modifier, so the bar, the search circle and the map's own controls
/// cannot drift apart.
struct GlassSurface: ViewModifier {
    /// What the surface is cut to.
    enum Outline {
        case capsule
        case circle
        case rounded(CGFloat)
    }

    var outline: Outline = .rounded(22)

    /// Liquid Glass arrived with the iOS 26 SDK, which is Xcode 26 - and the project has
    /// to keep compiling on the older toolchain CI runs. `compiler(>=6.2)` is that
    /// boundary: a build from Xcode 26 or later draws glass, an older one draws the
    /// frosted material, and the runtime check inside keeps iOS 18 devices frosted even
    /// when the app was built with a newer Xcode.
    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular, in: shape)
            } else {
                frosted(content)
            }
        #else
            frosted(content)
        #endif
    }

    private func frosted(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .overlay {
                // A hairline where the glass meets the map: without it the frosted
                // surface has no edge at all on a pale map.
                shape.stroke(.white.opacity(0.3), lineWidth: 0.5)
            }
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
