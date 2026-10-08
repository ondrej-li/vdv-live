import SwiftUI

/// Marker drawn for one ``VehicleCluster``.
///
/// A single vehicle shows its line number, a merged cluster shows how many
/// vehicles it stands for. The shape stays small on purpose: at region zoom
/// there can be a few hundred of them.
struct VehicleAnnotationView: View {
    let cluster: VehicleCluster
    let isSelected: Bool
    /// At least one vehicle in this marker is on a pinned line.
    let isFavourite: Bool

    var body: some View {
        badge
            .overlay(alignment: .topTrailing) { favouriteStar }
            // A vehicle the feed has stopped mentioning keeps its place, drawn
            // grey: last known, not fiction.
            .grayscale(cluster.isStale ? 1 : 0)
            .opacity(cluster.isStale ? 0.55 : 1)
            .scaleEffect(isSelected ? 1.2 : 1)
            .animation(.easeOut(duration: 0.15), value: isSelected)
            .animation(.easeOut(duration: 0.3), value: cluster.isStale)
            .accessibilityLabel(accessibilityTitle)
    }

    /// Voice over says the same thing the grey says to the eye, and the delay the
    /// border says.
    private var accessibilityTitle: String {
        if cluster.isStale {
            return "\(cluster.title), \(String(localized: "no recent data"))"
        }
        guard let delay = worstDelay, delay.isBadlyLate else { return cluster.title }
        return "\(cluster.title), \(delay.displayText)"
    }

    /// What the border says, before a tap: the line is pinned, or the vehicle is
    /// running badly late.
    ///
    /// Late wins, because it is the one that changes plans, and nothing is lost
    /// by it: the star is drawn on the badge separately from the border.
    private var borderColour: Color {
        isBadlyDelayed ? .red : (isFavourite ? VehicleFilter.favouriteTint : .white.opacity(0.9))
    }

    private var borderWidth: CGFloat {
        isBadlyDelayed || isFavourite ? 2 : 1.5
    }

    /// Whether any vehicle this marker stands for is badly late. A merged marker
    /// has to say so, because tapping it is how the user finds out which one.
    private var isBadlyDelayed: Bool {
        worstDelay?.isBadlyLate == true
    }

    /// The delay of the vehicle running furthest behind.
    private var worstDelay: VehicleDelay? {
        cluster.vehicles
            .compactMap(\.delay.minutes)
            .max()
            .map(VehicleDelay.minutes)
    }

    @ViewBuilder
    private var favouriteStar: some View {
        if isFavourite {
            Image(systemName: "star.fill")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.black)
                .frame(width: 14, height: 14)
                .background(VehicleFilter.favouriteTint, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1))
                .offset(x: 5, y: -5)
                .accessibilityHidden(true)
        }
    }

    private var badge: some View {
        Text(badgeText)
            .font(.caption2.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(minWidth: 22)
            .background(
                LinearGradient(
                    colors: [cluster.dominantTraction.tint.opacity(0.95), cluster.dominantTraction.tint],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(
                    borderColour,
                    lineWidth: borderWidth
                )
            )
    }

    private var badgeText: String {
        guard let vehicle = cluster.singleVehicle else {
            return "\(cluster.count)"
        }
        return vehicle.displayLine
    }
}
