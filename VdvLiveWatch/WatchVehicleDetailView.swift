import SwiftUI

/// What a tap on a vehicle says: which line, where it is going, and how late it
/// is. Nothing more - the watch is not the place for a timetable.
struct WatchVehicleDetailView: View {
    let vehicle: Vehicle

    @Environment(\.dismiss) private var dismiss

    private var band: DelayBand { DelayBand(vehicle.delay) }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text(vehicle.displayLine)
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(band.onTint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(band.tint, in: Capsule())

                // The same shorthand as the phone's card: the destination is the
                // headline, and its absence is said rather than left blank.
                Text(vehicle.destination ?? String(localized: "Destination not reported"))
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text(vehicle.delay.displayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(vehicle.traction.displayName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Button(String(localized: "Done")) { dismiss() }
                    .padding(.top, 4)
            }
            .padding(.horizontal, 4)
        }
    }
}
