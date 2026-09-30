import CoreLocation

/// The user's position, asked for once, when the map needs to open on it.
///
/// Behind a protocol because CoreLocation cannot be driven from a unit test, and
/// the behaviour worth testing here - which viewport the map opens on - does not
/// need a satellite to be worth testing.
@MainActor
protocol LocationProviding: Sendable {
    /// Asks for permission when it has never been asked for, then waits for one
    /// position.
    ///
    /// Returns `nil` when permission was refused, when the position cannot be
    /// determined, or when it takes too long to arrive.
    func requestCurrentCoordinate() async -> CLLocationCoordinate2D?
}

/// CoreLocation backed provider.
@MainActor
final class SystemLocationProvider: LocationProviding {
    /// How long to wait for permission to be answered and a position to arrive.
    /// Long enough for someone to read the prompt, short enough that a map which
    /// has already opened does not jump to the user much later.
    static let timeout: Duration = .seconds(8)

    /// Made on first use rather than in `init`, so that building the app's
    /// dependency stack does not have to happen on the main actor.
    private var manager: CLLocationManager?

    nonisolated init() {}

    func requestCurrentCoordinate() async -> CLLocationCoordinate2D? {
        let manager = manager ?? CLLocationManager()
        self.manager = manager

        // Asking is what puts the prompt on screen. The answer does not come back
        // from this call, which is why the updates below are what is waited on:
        // they report a refusal, and the position once there is one.
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }

        let request = Task { () -> CLLocationCoordinate2D? in
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    if let location = update.location {
                        return location.coordinate
                    }
                    // A refusal is an answer. Anything else, such as the prompt
                    // still being on screen, is worth waiting out.
                    if update.authorizationDenied || update.authorizationDeniedGlobally
                        || update.authorizationRestricted {
                        return nil
                    }
                }
            } catch {
                return nil
            }
            return nil
        }

        let deadline = Task {
            try? await Task.sleep(for: Self.timeout)
            request.cancel()
        }
        defer { deadline.cancel() }

        return await request.value
    }
}
