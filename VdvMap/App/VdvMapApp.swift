import SwiftUI

@main
struct VdvMapApp: App {
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
    }

    var body: some Scene {
        WindowGroup {
            VehicleMapView()
        }
    }
}
