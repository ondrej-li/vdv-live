import Foundation
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

    /// How long a snapshot may take before the widget gives up on it.
    ///
    /// A provider that never calls back leaves the widget showing the previous
    /// timeline for ever, so the map is worth a deadline: without one, a map server
    /// that stops answering would freeze the widget rather than only emptying it.
    static let timeout: DispatchTimeInterval = .seconds(8)

    /// The map around a position, or `nil` when Apple Maps cannot be reached in time -
    /// in which case the widget keeps its plain background rather than showing an error.
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

        // Held for as long as the snapshot may take: the snapshotter must outlive the
        // request, and the local reference is what keeps it alive across the await.
        let snapshotter = MKMapSnapshotter(options: options)
        let answer = Answer()

        return await withCheckedContinuation { continuation in
            snapshotter.start { snapshot, _ in
                answer.finish(snapshot?.image, continuation)
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                answer.finish(nil, continuation)
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

    /// Resumes the continuation once, whether the map arrived first or the deadline did.
    private final class Answer: @unchecked Sendable {
        private let lock = NSLock()
        private var hasAnswered = false

        func finish(_ image: UIImage?, _ continuation: CheckedContinuation<UIImage?, Never>) {
            lock.lock()
            guard !hasAnswered else {
                lock.unlock()
                return
            }
            hasAnswered = true
            lock.unlock()
            continuation.resume(returning: image)
        }
    }
}
