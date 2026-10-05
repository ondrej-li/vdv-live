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

    /// Asks for permission to use the position, for the case where the map draws
    /// the position itself and nothing in the app needs a fix.
    ///
    /// Returns whether the app is allowed to use the position afterwards.
    @discardableResult
    func requestAuthorization() async -> Bool

    /// Positions as they arrive, for a map that draws the wearer's own dot.
    ///
    /// Starting this is what puts the permission prompt on screen the first time;
    /// a refusal ends the stream. It also keeps location running, so whoever reads
    /// it has to stop reading when the dot is no longer wanted.
    func positions() -> AsyncStream<CLLocationCoordinate2D>
}

/// CoreLocation backed provider.
@MainActor
final class SystemLocationProvider: LocationProviding {
    /// How long to wait for permission to be answered and a position to arrive.
    /// Long enough for someone to read the prompt, short enough that a map which
    /// has already opened does not jump to the user much later.
    static let timeout: Duration = .seconds(8)

    /// How long to wait for someone to answer the permission prompt. Longer than
    /// the wait for a fix, because a person reading a dialog is not a slow
    /// satellite.
    static let authorizationTimeout: Duration = .seconds(30)

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

    func requestAuthorization() async -> Bool {
        let manager = manager ?? CLLocationManager()
        self.manager = manager

        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            // Asking is all this provider can do: the answer arrives through a
            // delegate it does not have, and the status is a value the system
            // keeps, so it is read until it stops saying "not determined".
            let deadline = ContinuousClock.now + Self.authorizationTimeout
            while manager.authorizationStatus == .notDetermined, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        return Self.permitsLocation(manager.authorizationStatus)
    }

    func positions() -> AsyncStream<CLLocationCoordinate2D> {
        AsyncStream { continuation in
            let updates = Task {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if let coordinate = update.location?.coordinate {
                            continuation.yield(coordinate)
                        }
                        // A refusal is an answer, and so is the app going away.
                        if update.authorizationDenied || update.authorizationDeniedGlobally
                            || update.authorizationRestricted {
                            break
                        }
                        if Task.isCancelled { break }
                    }
                } catch {
                    // A stream that cannot start is the same as one that ended.
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in updates.cancel() }
        }
    }

    private static func permitsLocation(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }
}
