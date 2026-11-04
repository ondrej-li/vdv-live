import MapKit
import UIKit
import WidgetKit

/// A still map for the widget that has no vehicles to list.
///
/// WidgetKit draws snapshots rather than live maps, so this renders one frame of the
/// same Apple Maps the app shows, centred where the reader last was. It is the
/// answer to "nothing of mine is nearby": the map says where "nearby" is, without a
/// sentence claiming emptiness over a blank card.
enum WidgetMap {
    /// How much ground the widget covers: a few kilometres either way, which is the
    /// distance a bus is worth walking to and the one the traffic widget ranks by.
    static let spanMetres: CLLocationDistance = 4_000

    /// The map around a position, or `nil` when Apple Maps cannot be reached - in
    /// which case the widget keeps its plain background rather than showing an error.
    static func image(around coordinate: CLLocationCoordinate2D,
                      family: WidgetFamily) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: coordinate,
                                            latitudinalMeters: spanMetres,
                                            longitudinalMeters: spanMetres)
        options.size = size(for: family)
        options.mapType = .standard
        options.showsBuildings = false
        options.pointOfInterestFilter = .excludingAll

        return await withCheckedContinuation { continuation in
            MKMapSnapshotter(options: options).start { snapshot, _ in
                continuation.resume(returning: snapshot?.image)
            }
        }
    }

    /// The point size of a widget on the home screen, so the snapshot is drawn at the
    /// resolution the system will scale it to rather than stretched afterwards.
    static func size(for family: WidgetFamily) -> CGSize {
        switch family {
        case .systemSmall: return CGSize(width: 170, height: 170)
        case .systemLarge, .systemExtraLarge: return CGSize(width: 364, height: 382)
        default: return CGSize(width: 364, height: 170)
        }
    }
}
