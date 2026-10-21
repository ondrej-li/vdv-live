import Foundation

/// The stops the user starred.
///
/// A stop is identified by the name the timetable shows, because that is the only handle
/// a stop has: the archive publishes no stop ids that anything else can be joined to.
/// Names are compared washed down (case, diacritics, punctuation) so that a stop starred
/// from the map and the same stop typed into a search are one stop.
struct StarredStops: Hashable, Sendable {
    /// Display names, in the order they were starred, so the list can also be read as
    /// "what I added last".
    private(set) var names: [String] = []

    init<S: Sequence<String>>(_ names: S = []) {
        for name in names {
            guard !Self.key(for: name).isEmpty, !contains(name) else { continue }
            self.names.append(name)
        }
    }

    var isEmpty: Bool { names.isEmpty }
    var count: Int { names.count }

    func contains(_ name: String) -> Bool {
        let wanted = Self.key(for: name)
        guard !wanted.isEmpty else { return false }
        return names.contains { Self.key(for: $0) == wanted }
    }

    /// Stars the stop when it was not starred, unstars it otherwise.
    /// - Returns: whether the stop is starred after the change.
    @discardableResult
    mutating func toggle(_ name: String) -> Bool {
        if contains(name) {
            let wanted = Self.key(for: name)
            names.removeAll { Self.key(for: $0) == wanted }
            return false
        }
        guard !Self.key(for: name).isEmpty else { return false }
        names.append(name)
        return true
    }

    mutating func star(_ name: String) {
        guard !contains(name), !Self.key(for: name).isEmpty else { return }
        names.append(name)
    }

    mutating func unstar(_ name: String) {
        let wanted = Self.key(for: name)
        names.removeAll { Self.key(for: $0) == wanted }
    }

    /// Alphabetical, because a list of stops is looked things up in rather than
    /// browsed in the order they were added.
    var orderedForDisplay: [String] {
        names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The same washing the stop table itself is keyed by.
    static func key(for name: String) -> String {
        StopPositions.lookupKey(for: name)
    }
}
