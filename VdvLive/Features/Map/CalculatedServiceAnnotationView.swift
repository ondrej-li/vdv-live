import SwiftUI

/// Marker for a service the timetable says is out, where the feed reports nothing.
///
/// It has to read as different at a glance: a vehicle's badge carries a traction
/// colour and a solid border, while this one is drawn in a dashed amber outline
/// with an exclamation triangle on its corner. Nothing here is a measurement, and
/// the marker says so before the user has tapped anything.
struct CalculatedServiceAnnotationView: View {
    let service: ExpectedService

    /// Amber, which no traction uses, so a calculated marker cannot be mistaken
    /// for a colour a vehicle already means.
    static let tint = Color.orange

    var body: some View {
        badge
            .overlay(alignment: .topTrailing) { warningTriangle }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityTitle)
    }

    private var accessibilityTitle: String {
        String(
            format: String(localized: "Line %@, calculated position"),
            service.displayLine
        )
    }

    private var badge: some View {
        Text(service.displayLine)
            .font(.caption2.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(minWidth: 22)
            .background(Color.black.opacity(0.7), in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    Self.tint,
                    style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])
                )
            )
    }

    /// The exclamation triangle, on the corner the pinned star uses, so a marker
    /// with neither is a measured position.
    private var warningTriangle: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 13, weight: .black))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.black, Self.tint)
            .shadow(color: .white.opacity(0.9), radius: 0.5)
            .offset(x: 7, y: -7)
            .accessibilityHidden(true)
    }
}
