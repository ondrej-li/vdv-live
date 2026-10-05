#if DEBUG
import CoreLocation
import Foundation

/// Stand-in for the network, used by SwiftUI previews and by nothing else.
///
/// The vehicles sit in and around Jihlava, Třebíč, Žďár nad Sázavou, Havlíčkův
/// Brod and Pelhřimov, which is where the real feed is busiest.
struct SampleVehicleFetcher: VehicleFetching {
    /// Small pause so previews show the loading state for a moment.
    var delay: Duration = .milliseconds(300)

    func fetchVehicles() async throws -> VehiclePayload {
        try? await Task.sleep(for: delay)
        return VehiclePayload(
            vehicles: Self.vehicles,
            skippedRecordCount: 1,
            unlocatableRecordCount: 1
        )
    }

    static let vehicles: [Vehicle] = [
        Vehicle(
            id: 1,
            line: "841334",
            latitude: 49.3960,
            longitude: 15.5910,
            destination: "Bystřice n.Pern.,aut.nádr.",
            delay: .minutes(5),
            traction: .bus
        ),
        Vehicle(
            id: 2,
            line: "841102",
            latitude: 49.3930,
            longitude: 15.5860,
            destination: "Velké Meziříčí,aut.nádr.",
            delay: .minutes(-2),
            traction: .bus
        ),
        Vehicle(
            id: 3,
            line: "764330",
            latitude: 49.2150,
            longitude: 15.8810,
            destination: "Třebíč,aut.nádr.",
            delay: .minutes(0),
            traction: .bus
        ),
        Vehicle(
            id: 4,
            line: "842135",
            latitude: 49.5627,
            longitude: 15.9400,
            destination: "Nové Město na Mor.,centrum",
            delay: .unknown,
            traction: .bus
        ),
        Vehicle(
            id: 5,
            line: "5435405",
            latitude: 49.5532,
            longitude: 15.9416,
            destination: nil,
            delay: .minutes(1),
            traction: .train
        ),
        Vehicle(
            id: 6,
            line: "357301",
            latitude: 49.4310,
            longitude: 15.2230,
            destination: "Pelhřimov,aut.nádr.",
            delay: .minutes(357),
            traction: .unknown
        ),
        Vehicle(
            id: 7,
            line: "603225",
            latitude: 49.6070,
            longitude: 15.5810,
            destination: "Havlíčkův Brod,Dopravní terminál",
            delay: .minutes(2),
            traction: .bus
        ),
        Vehicle(
            id: 8,
            line: "796452",
            latitude: 49.2080,
            longitude: 15.8997,
            destination: "Třebíč,aut.nádr.",
            delay: .minutes(12),
            traction: .bus
        )
    ]
}

/// Detail popup used by previews: no network, plausible values.
struct SampleVehicleDetailFetcher: VehicleDetailFetching {
    func fetchDetail(for vehicle: Vehicle) async throws -> VehicleDetail {
        try? await Task.sleep(for: .milliseconds(400))
        return VehicleDetail(
            lineCode: vehicle.lineCode,
            serviceNumber: "11",
            isBarrierFree: true,
            stopName: "Jihlava,aut.nádr.",
            reportedDelayMinutes: vehicle.delay.minutes,
            runStops: [
                RunStop(name: "Jihlava,aut.nádr.", arrival: "14:06", departure: "14:06"),
                RunStop(name: "Jihlava,Brněnská", arrival: "14:12", departure: "14:12"),
                RunStop(name: "Velké Meziříčí,aut.nádr.", arrival: "14:31", departure: "14:33"),
                RunStop(name: "Bystřice n.Pern.,aut.nádr.", arrival: "14:52", departure: "14:52")
            ]
        )
    }
}

/// Position used by previews: Jihlava, where most of the sample vehicles are.
@MainActor
struct SampleLocationProvider: LocationProviding {
    var coordinate: CLLocationCoordinate2D? = CLLocationCoordinate2D(
        latitude: 49.3960,
        longitude: 15.5910
    )

    /// `nonisolated` for the same reason as the real provider: the preview
    /// dependency stack is built away from the main actor.
    nonisolated init() {}

    func requestCurrentCoordinate() async -> CLLocationCoordinate2D? {
        try? await Task.sleep(for: .milliseconds(200))
        return coordinate
    }

    func requestAuthorization() async -> Bool { true }

    /// Hands the preview position over once and ends, the same shape as the real
    /// provider in a place that never moves.
    func positions() -> AsyncStream<CLLocationCoordinate2D> {
        guard let coordinate else {
            return AsyncStream { $0.finish() }
        }
        return AsyncStream { continuation in
            continuation.yield(coordinate)
            continuation.finish()
        }
    }
}
#endif
