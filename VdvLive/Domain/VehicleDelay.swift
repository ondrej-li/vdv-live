import Foundation

/// How far a vehicle is off its timetable, in minutes.
///
/// The feed uses `Int32.min` (`-2147483648`) as the value for "not known",
/// which is how about a third of the records arrive. Negative values are
/// legitimate and mean the vehicle is ahead of schedule.
enum VehicleDelay: Codable, Hashable, Sendable {
    case unknown
    case minutes(Int)

    /// Value the feed writes when it has no delay to report.
    static let unknownSentinel = Int(Int32.min)

    init(rawMinutes: Int) {
        self = rawMinutes == Self.unknownSentinel ? .unknown : .minutes(rawMinutes)
    }

    /// Delay in minutes, `nil` when the feed has no value.
    var minutes: Int? {
        switch self {
        case .unknown: return nil
        case .minutes(let value): return value
        }
    }

    var isKnown: Bool { minutes != nil }

    /// Minutes behind schedule at which a vehicle is worth warning about rather
    /// than merely being a little behind.
    ///
    /// Five, because that is where the card already draws its line between
    /// orange and red, and a second threshold for the map would only disagree
    /// with it eventually.
    static let badlyLateMinutes = 5

    /// Whether the vehicle is late enough to be pointed out.
    var isBadlyLate: Bool {
        guard let minutes else { return false }
        return minutes >= Self.badlyLateMinutes
    }
}
