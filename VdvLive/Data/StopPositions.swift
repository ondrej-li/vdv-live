import CoreLocation
import Foundation

/// Where a stop is, as far as we could work out.
///
/// The timetables ship stop names but no geometry: JDF has no coordinate columns and the
/// ministry's NeTEx export leaves every stop's `<Location />` empty. Positions are matched
/// from OpenStreetMap by name where they can be, and the village centre is used where they
/// cannot - which is why every position says how it was found and how close it is likely
/// to be. `docs/stops.md` has the measurements and `tools/stop_positions.py` builds the file.
struct StopPosition: Equatable, Decodable, Sendable {
    /// How the position was arrived at. Lower accuracy means less trust.
    enum Match: String, Decodable, Sendable {
        /// An OpenStreetMap stop whose name is this stop's name.
        case name = "osm-name"
        /// An OpenStreetMap stop in the same village carrying the same local name.
        case village = "osm-village"
        /// An OpenStreetMap stop named after the hamlet the stop is in, found by proximity.
        case near = "osm-near"
        /// No stop of this name was found, so the village centre is the position.
        case place
    }

    /// The stop name the position was matched for, as the app displays it.
    let name: String
    let latitude: Double
    let longitude: Double
    let match: Match
    /// Roughly how far the position can be out, in metres.
    let accuracyMetres: Double

    /// Where the stop is, for anything that draws.
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// True when the position belongs to the stop itself rather than to its village.
    var isExact: Bool { match != .place }
}

/// The shipped stop positions, looked up by the stop name the timetable shows.
///
/// The keys in the file are already washed down to letters and digits, so a name has to be
/// washed the same way before it is looked up: `Okříšky,aut.nádr.` and `Okrisky, aut. nadr.`
/// are the same key.
struct StopPositions: Sendable {
    private let positions: [String: StopPosition]

    static let empty = StopPositions(positions: [:])

    init(positions: [String: StopPosition]) {
        self.positions = positions
    }

    /// The table that ships with the app, or an empty one if it cannot be read.
    static func bundled(in bundle: Bundle = .main) -> StopPositions {
        guard let url = bundle.url(forResource: "stop-positions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(Document.self, from: data) else {
            return .empty
        }
        return StopPositions(positions: document.stops)
    }

    /// The position of a stop, given the name the app shows for it.
    func position(forStopNamed name: String) -> StopPosition? {
        positions[Self.lookupKey(for: name)]
    }

    /// The stops inside a rectangle, which is what a map layer needs.
    ///
    /// Plain ranges rather than a map region, so the rule can be tested without
    /// a map, and sorted by name so the flags are drawn in a stable order.
    func positions(latitude: ClosedRange<Double>,
                   longitude: ClosedRange<Double>) -> [StopPosition] {
        positions.values
            .filter { latitude.contains($0.latitude) && longitude.contains($0.longitude) }
            .sorted { $0.name < $1.name }
    }

    var count: Int { positions.count }

    /// Case, diacritics, spaces and punctuation washed out, matching how the file is keyed.
    static func lookupKey(for name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                  locale: Locale(identifier: "en_US_POSIX"))
        return folded.unicodeScalars.reduce(into: "") { key, scalar in
            if CharacterSet.alphanumerics.contains(scalar) {
                key.unicodeScalars.append(scalar)
            }
        }
    }

    private struct Document: Decodable {
        let stops: [String: StopPosition]
    }
}
