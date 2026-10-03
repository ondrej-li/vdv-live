import SwiftUI

/// Marker drawn for one stop whose position is known.
///
/// A flag, and small: a stop is a fixed point the reader looks up rather than
/// something that moves, and the flags only appear once the map is zoomed in far
/// enough to read them. Where the positions come from, and why not every stop has
/// one, is in `docs/stops.md`.
struct StopAnnotationView: View {
    let stop: StopPosition

    var body: some View {
        Image(systemName: "flag.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Color.accentColor, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .accessibilityLabel(Text(stop.name))
    }
}
