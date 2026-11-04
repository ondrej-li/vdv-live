import SwiftUI

/// The few colours a widget has room for.
///
/// Deliberately not the map's design system: a widget draws on the system's own
/// background, so it needs the plain semantic colours rather than the translucent
/// ones a card over a map uses. The delay bands are the same as the map's, because
/// a reader who has learnt that amber means five minutes behind should not have to
/// learn a second scale on the home screen.
enum WidgetPalette {
    static func delayTint(_ delay: VehicleDelay) -> Color {
        switch delay {
        case .unknown:
            return .secondary
        case .minutes(let minutes):
            if delay.isBadlyLate { return .red }
            return minutes > 0 ? .orange : .green
        }
    }

    /// The delay of a board row, which is only known once a vehicle reports.
    static func delayTint(minutes: Int?) -> Color {
        guard let minutes else { return .secondary }
        if minutes >= VehicleDelay.badlyLateMinutes { return .red }
        return minutes > 0 ? .orange : .green
    }

    /// The colour of a row's status: the same scale as the map, and grey while the
    /// timetable is all the widget has to go on.
    static func statusTint(_ status: StopBoardEntry.Status) -> Color {
        switch status {
        case .scheduled: return .secondary
        case .onTime, .early: return .green
        case .late(let minutes):
            return minutes >= VehicleDelay.badlyLateMinutes ? .red : .orange
        }
    }
}

extension NearbyVehicle {
    /// Distance as a person reads it: metres close by, whole kilometres beyond.
    var distanceText: String {
        if distanceMetres < 1_000 {
            return String(format: String(localized: "%lld m"), Int(distanceMetres.rounded()))
        }
        let kilometres = distanceMetres / 1_000
        return String(format: String(localized: "%.1f km"), kilometres)
    }
}
