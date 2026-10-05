import SwiftUI

@main
struct VdvLiveApp: App {
    /// Keeps the watch's copy of the pinned lines current, wherever they are
    /// pinned from. Started here rather than in a screen so the watch hears about
    /// a change made anywhere in the app.
    private let watchFavourites = WatchFavouritesPublisher()

    @MainActor
    init() {
        // iOS decides which translation to use while the app starts, so the
        // stored choice is written before the first view is built. Changing the
        // language therefore shows up the next time the app is launched, which
        // is exactly what the settings screen says.
        //
        // Skipped while tests run: the test host is this very app, and writing
        // the language there would change the language the tests themselves see.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }
        LanguageOverride.apply(UserDefaultsAppSettingsStore().load().language)
        watchFavourites.start()
    }

    var body: some Scene {
        WindowGroup {
            VehicleMapView()
        }
    }
}
