import Foundation

/// How a tracked vehicle moves.
///
/// Mirrors the `traction` field of `/Ajax/GetPoints`. The feed is maintained by
/// a third party and may grow new values at any time, so anything unrecognised
/// is mapped onto ``Traction/unknown`` instead of failing a decode.
enum Traction: String, CaseIterable, Codable, Hashable, Sendable {
    case bus = "BUS"
    case trolleybus = "TROLLEYBUS"
    case tram = "TRAM"
    case train = "TRAIN"
    case ferry = "FERRY"
    case unknown = "UNKNOWN"

    init(serverValue: String) {
        let normalized = serverValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        self = Traction(rawValue: normalized) ?? .unknown
    }

    /// Stable order used for filter menus and for picking the colour of a
    /// cluster that mixes several tractions.
    var sortIndex: Int {
        switch self {
        case .bus: return 0
        case .trolleybus: return 1
        case .tram: return 2
        case .train: return 3
        case .ferry: return 4
        case .unknown: return 5
        }
    }
}

extension Traction: Identifiable {
    var id: String { rawValue }
}

extension Traction {
    /// What to call this traction in a line summary.
    ///
    /// Text rather than colour, so it belongs with the model: the phone's colours
    /// and symbols live in the design system beside the views that use them, and
    /// the watch draws none of them but still has to name a line's traction.
    var displayName: String {
        switch self {
        case .bus: return String(localized: "Bus")
        case .trolleybus: return String(localized: "Trolleybus")
        case .tram: return String(localized: "Tram")
        case .train: return String(localized: "Train")
        case .ferry: return String(localized: "Ferry")
        case .unknown: return String(localized: "Unknown")
        }
    }
}
