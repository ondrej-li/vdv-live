import MapKit
import SwiftUI

/// The whole watch app: a map of the pinned lines' vehicles, and nothing else.
///
/// No menu, no filter, no favourite star - the lines shown are the ones already
/// pinned on the phone, so every dot on screen is a favourite by definition. What
/// the dot cannot say in words it says in colour, and the digital crown is the
/// zoom.
struct WatchMapView: View {
    @State private var model = WatchVehicleMapModel(fetcher: WatchVehicleSource.fetcher)
    @State private var camera: MapCameraPosition = .region(RegionOfInterest.vysocina.region)
    @State private var region: MKCoordinateRegion = RegionOfInterest.vysocina.region
    @State private var zoom: Double = MapZoom.initialCrownValue

    var body: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom]) {
            ForEach(model.vehicles) { vehicle in
                Annotation("", coordinate: vehicle.coordinate) {
                    WatchVehicleDot(band: DelayBand(vehicle.delay))
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .onMapCameraChange(frequency: .continuous) { context in
            // Panning and pinching move the map; the next crown turn has to start
            // from where the finger left it.
            region = context.region
        }
        .digitalCrownRotation(
            $zoom,
            from: 0,
            through: 1,
            by: 0.01,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: false
        )
        .onChange(of: zoom) { _, value in crownTurned(to: value) }
        .overlay(alignment: .bottom) { status }
        .task { await model.start() }
        .onDisappear { model.stopAutoRefresh() }
    }

    private func crownTurned(to value: Double) {
        var updated = region
        updated.span = MapZoom.span(forCrownValue: value)
        region = updated
        camera = .region(updated)
    }

    /// Something worth saying, and nothing at all otherwise.
    @ViewBuilder
    private var status: some View {
        if model.favouriteLines.isEmpty {
            note(String(localized: "Pin lines on the phone"))
        } else if model.isLoading, model.vehicles.isEmpty {
            ProgressView()
                .padding(6)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 6)
        } else if let message = model.errorMessage, model.vehicles.isEmpty {
            note(message)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 6)
    }
}

/// One vehicle: a dot whose colour is its delay band, and nothing else.
struct WatchVehicleDot: View {
    let band: DelayBand

    var body: some View {
        Circle()
            .fill(band.tint)
            .frame(width: 15, height: 15)
            .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 1))
    }
}
