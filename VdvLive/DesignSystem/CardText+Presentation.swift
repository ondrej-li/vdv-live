import SwiftUI

extension Color {
    /// Text that reads as secondary on the card, which is drawn over a material.
    ///
    /// The card is not a plain surface: it sits on `.regularMaterial` over the map.
    /// A semantic label colour there is blended with whatever is behind the card
    /// instead of being drawn on it, and once the card is clipped to the height it
    /// is currently showing - which is what makes it a drawer - that blend swallows
    /// the text whole. An explicit colour is left alone, so the card uses this one.
    static let cardSecondary = Color.primary.opacity(0.55)

    /// The drawer's grabber, which has to read as a thing to be pulled. It is a
    /// shape rather than text, so it needs its own colour for the same reason.
    static let cardHandle = Color.primary.opacity(0.22)
}
