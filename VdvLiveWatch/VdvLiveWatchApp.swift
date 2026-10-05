import SwiftUI

/// VDV Live on the wrist: the pinned lines, and how late they are.
@main
struct VdvLiveWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchMapView()
        }
    }
}
