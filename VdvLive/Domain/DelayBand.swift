import Foundation

/// How far off schedule a vehicle is, in the three bands the watch colours by.
///
/// The phone splits delay around five minutes: everything from five up is painted
/// the same red, because a marker there carries the line number and the delay in
/// words beside it. The watch has room for a dot and nothing else, so the colour
/// has to say more on its own - green while the vehicle is on time or up to five
/// minutes behind, amber from five to ten, red beyond that.
///
/// The five minute edge belongs to green, which is what "on time or maximum five
/// minutes delay" means when the next band starts at five.
enum DelayBand: Hashable, Sendable {
    /// On time, early, or no more than ``lateMinutes`` behind.
    case onTime
    /// More than ``lateMinutes`` and no more than ``veryLateMinutes`` behind.
    case late
    /// More than ``veryLateMinutes`` behind.
    case veryLate
    /// The feed did not say how late the vehicle is.
    case unknown

    /// The largest delay, in minutes, still banded as on time.
    static let lateMinutes = 5
    /// The largest delay, in minutes, still banded as merely late.
    static let veryLateMinutes = 10

    init(_ delay: VehicleDelay) {
        guard let minutes = delay.minutes else {
            self = .unknown
            return
        }
        if minutes > Self.veryLateMinutes {
            self = .veryLate
        } else if minutes > Self.lateMinutes {
            self = .late
        } else {
            self = .onTime
        }
    }
}
