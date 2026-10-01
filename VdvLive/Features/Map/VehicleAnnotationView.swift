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

    /// Voice over says the same thing the grey says to the eye.
    private var accessibilityTitle: String {
        cluster.isStale
            ? "\(cluster.title), \(String(localized: "no recent data"))"
            : cluster.title
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
                    isFavourite ? VehicleFilter.favouriteTint : .white.opacity(0.9),
                    lineWidth: isFavourite ? 2 : 1.5
                )
            )
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }

    private var badgeText: String {
        guard let vehicle = cluster.singleVehicle else {
            return "\(cluster.count)"
        }
        return vehicle.displayLine
    }
}
