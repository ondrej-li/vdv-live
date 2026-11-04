import AppIntents
import Foundation

/// A stop as the widget's configuration knows it.
///
/// The name is the identifier, for the same reason it is everywhere else in the
/// app: the archive publishes no stop id that anything can be joined to, and the
/// name is what the timetable and the shipped table are keyed by.
struct StopEntity: AppEntity, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Stop")
    static let defaultQuery = StopEntityQuery()

    let name: String

    var id: String { name }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

/// Turns the stop table into the search field the widget's configuration shows.
struct StopEntityQuery: EntityStringQuery {
    func entities(for identifiers: [StopEntity.ID]) async throws -> [StopEntity] {
        identifiers.map { StopEntity(name: $0) }
    }

    func entities(matching string: String) async throws -> [StopEntity] {
        StopIndex.matching(string).map { StopEntity(name: $0) }
    }

    func suggestedEntities() async throws -> [StopEntity] {
        StopIndex.suggested().map { StopEntity(name: $0) }
    }
}
