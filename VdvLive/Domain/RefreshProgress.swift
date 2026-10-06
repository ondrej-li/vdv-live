import Foundation

/// How far a map is from its next automatic refresh.
///
/// The phone draws this as the top edge of its header card and the watch as a
/// hairline across the screen. Both read it from here, so the two cannot disagree
/// about what the bar means, and the arithmetic stays out of the views where it
/// could not be tested.
enum RefreshProgress {
    /// The fraction of the interval that has passed, clamped to `0...1`.
    ///
    /// `1` means due: either the interval has gone by, or there is no fetch to count
    /// from at all - a map that has never loaded has nothing to wait for, and a bar
    /// that reads as full is the honest picture of that.
    static func fraction(lastUpdatedAt: Date?, now: Date, interval: TimeInterval) -> Double {
        guard let lastUpdatedAt else { return 1 }
        return fraction(elapsed: now.timeIntervalSince(lastUpdatedAt), interval: interval)
    }

    /// The same, for a caller that has already measured the elapsed time.
    static func fraction(elapsed: TimeInterval, interval: TimeInterval) -> Double {
        guard interval > 0, elapsed.isFinite else { return 1 }
        return min(max(elapsed / interval, 0), 1)
    }
}
