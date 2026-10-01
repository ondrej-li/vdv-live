import SwiftUI

/// Small legend that says how long a stretch of the map is.
///
/// A bar of exactly the length ``MapScale/barLength`` stands for, with the
/// distance next to it, so a marker a few centimetres away can be read as "that
/// bus is about 5 km from here".
struct MapScaleLegend: View {
    let scale: MapScale

    var body: some View {
        HStack(spacing: 8) {
            bar
            Text(scale.labelText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.1), radius: 5, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Map scale"))
        .accessibilityValue(Text(scale.labelText))
    }

    private var bar: some View {
        HStack(spacing: 0) {
            tick
            Rectangle()
                .fill(.primary.opacity(0.55))
                .frame(height: 1)
            tick
        }
        .frame(width: scale.barLength, height: 8)
    }

    private var tick: some View {
        Rectangle()
            .fill(.primary.opacity(0.55))
            .frame(width: 1, height: 8)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        MapScaleLegend(scale: MapScale(distanceMetres: 500, barLength: 70))
        MapScaleLegend(scale: MapScale(distanceMetres: 5_000, barLength: 90))
        MapScaleLegend(scale: MapScale(distanceMetres: 50_000, barLength: 60))
    }
    .padding(40)
}
