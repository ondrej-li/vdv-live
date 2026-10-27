import CoreLocation
import Foundation

/// Where a stop is, as far as we could work out.
///
/// The timetables ship stop names but no geometry: JDF has no coordinate columns and the
/// ministry's NeTEx export leaves every stop's `<Location />` empty. Positions are matched
/// from OpenStreetMap by name where they can be, and the village centre is used where they
/// cannot - which is why every position says how it was found and how close it is likely
/// to be. `docs/stops.md` has the measurements and
/// `.github/skills/stop-positions/SKILL.md` rebuilds the file.
struct StopPosition: Equatable, Decodable, Sendable {
    /// How the position was arrived at. Lower accuracy means less trust.
    enum Match: String, Decodable, Sendable {
        /// An OpenStreetMap stop whose name is this stop's name.
        case name = "osm-name"
        /// An OpenStreetMap stop in the same village carrying the same local name.
        case village = "osm-village"
        /// An OpenStreetMap stop named after the hamlet the stop is in, found by proximity.
        case near = "osm-near"
        /// An OpenStreetMap stop whose name contains this stop's, near the line it is on.
        case similar = "osm-similar"
        /// No stop of this name was found, so the village centre is the position.
        case place
        /// Nothing nameable was found at all; the point sits between the stops either side
        /// of this one on the line, so it is only good enough to draw somewhere to climb on.
        case route
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

    /// True when the position belongs to the stop itself rather than to its village or to
    /// the gap between the stops either side of it on the line.
    var isExact: Bool { match != .place && match != .route }
}

/// The shipped stop positions, looked up by the stop name the timetable shows.
///
/// The keys in the file are already washed down to letters and digits, so a name has to be
/// washed the same way before it is looked up: `Okříšky,aut.nádr.` and `Okrisky, aut. nadr.`
/// are the same key.
struct StopPositions: Sendable {
    private let positions: [String: StopPosition]
    private let lines: [String: [String]]

    static let empty = StopPositions(positions: [:], lines: [:])

    /// The shipped table, read once. It is half a megabyte of JSON and the stop search
    /// asks for its names on every keystroke.
    static let shipped = bundled()

    init(positions: [String: StopPosition], lines: [String: [String]] = [:]) {
        self.positions = positions
        self.lines = lines
    }

    /// The table that ships with the app, or an empty one if it cannot be read.
    static func bundled(in bundle: Bundle = .main) -> StopPositions {
        guard let url = bundle.url(forResource: "stop-positions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(Document.self, from: data) else {
            return .empty
        }
        return StopPositions(positions: document.stops, lines: document.stopLines ?? [:])
    }

    /// The position of a stop, given the name the app shows for it.
    func position(forStopNamed name: String) -> StopPosition? {
        positions[Self.lookupKey(for: name)]
    }

    /// The lines that call at a stop, by the archive's own code - `764350`, the number the
    /// line's timetable and the mapping are filed under.
    ///
    /// This is what a board needs before it can have rows: the timetables are per line, so
    /// a stop's departures are the departures of the lines that stop here, and nothing else.
    /// Empty for a stop the table does not name, which is a stop with no rows rather than
    /// an error.
    func lines(atStopNamed name: String) -> [String] {
        lines[Self.lookupKey(for: name)] ?? []
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

    /// Every stop name the table can place, sorted, which is what a search field offers.
    var allNames: [String] {
        positions.values.map(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Stop names matching what was typed, the way people type: `nova brtnice` finds
    /// `Nová Brtnice`, and a slipped letter (`nova betnice`) still finds it.
    ///
    /// Both sides are washed down to the key the file is already keyed by, which drops
    /// case, diacritics, spaces and punctuation - the same fold the positions and the
    /// lines are looked up by, so the search cannot disagree with the rest of the app.
    /// ``StopNameMatching`` ranks the answers, so a name that begins with the text
    /// comes before one that merely contains it.
    func names(matching text: String,
               excluding isExcluded: (String) -> Bool = { _ in false },
               limit: Int = 20) -> [String] {
        guard !StopNameMatching.key(for: text).isEmpty else { return [] }

        let found = positions.values
            .compactMap { position -> (name: String, quality: StopNameMatching.Quality)? in
                guard !isExcluded(position.name),
                      let quality = StopNameMatching.quality(of: position.name, matching: text) else {
                    return nil
                }
                return (position.name, quality)
            }

        return found
            .sorted { lhs, rhs in
                if lhs.quality != rhs.quality { return lhs.quality < rhs.quality }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            .prefix(limit)
            .map(\.name)
    }

    /// Case, diacritics, spaces and punctuation washed out, matching how the file is keyed.
    static func lookupKey(for name: String) -> String {
        StopNameMatching.key(for: name)
    }

    private struct Document: Decodable {
        let stops: [String: StopPosition]
        /// Missing in a bundle built before the board needed it, which is why it is optional.
        let stopLines: [String: [String]]?
    }
}
