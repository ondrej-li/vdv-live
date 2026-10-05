import SwiftUI

/// One vehicle on the watch: its line number, coloured by how late it is.
///
/// The phone's marker carries more than this - a favourite star, a greyed out
/// state for a vehicle that has gone quiet, a count for a merged cluster - but a
/// wrist has room for two things, and the line number and the delay colour are
/// the two that answer the only question being asked.
struct WatchVehicleBadge: View {
    let vehicle: Vehicle

    private var band: DelayBand { DelayBand(vehicle.delay) }

    var body: some View {
        Text(vehicle.displayLine)
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(band.onTint)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(band.tint, in: Capsule())
            .overlay(Capsule().strokeBorder(.black.opacity(0.35), lineWidth: 1))
            .accessibilityLabel(accessibilityTitle)
    }

    private var accessibilityTitle: String {
        "\(vehicle.displayLine), \(vehicle.delay.displayText)"
    }
}
