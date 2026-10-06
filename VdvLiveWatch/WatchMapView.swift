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
    /// The vehicle whose destination is being shown, if any.
    @State private var selected: Vehicle?

    var body: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom], selection: $selected) {
            // Where the wearer is, drawn here rather than with SwiftUI's own
            // `UserAnnotation`, which compiles for watchOS but puts nothing on the
            // map. Always on: a bus two kilometres away is only useful next to it.
            if let coordinate = model.userCoordinate {
                Annotation("", coordinate: coordinate) {
                    WatchUserDot()
                }
            }

            ForEach(model.vehicles) { vehicle in
                Annotation("", coordinate: vehicle.coordinate) {
                    WatchVehicleBadge(vehicle: vehicle)
                }
                .tag(vehicle)
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
        .sheet(item: $selected) { vehicle in
            WatchVehicleDetailView(vehicle: vehicle)
        }
        .overlay(alignment: .bottom) { status }
        .overlay(alignment: .top) {
            // The phone's header carries the same hairline along its top edge; a
            // wrist gets the bar without the card.
            WatchRefreshProgressBar(
                interval: WatchVehicleMapModel.refreshInterval,
                lastUpdatedAt: model.lastUpdatedAt
            )
        }
        .task {
            await model.start()
            if selectsFirstVehicle { selected = model.vehicles.first }
        }
        .onDisappear { model.stop() }
    }

    /// `-watchSelectFirst` opens the detail sheet on launch, which is otherwise
    /// only reachable by tapping a marker and so cannot be photographed in a
    /// simulator.
    private var selectsFirstVehicle: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-watchSelectFirst")
        #else
        return false
        #endif
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
        } else if let message = model.errorMessage {
            // Said even when the map has vehicles on it: those are the last
            // positions the watch managed to fetch, and a marker that is stale but
            // looks live is worse than one that is labelled.
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

/// Where the wearer is: the same blue dot the phone's map draws for itself.
struct WatchUserDot: View {
    var body: some View {
        Circle()
            .fill(.blue)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(radius: 1)
            .accessibilityLabel(String(localized: "My location"))
    }
}