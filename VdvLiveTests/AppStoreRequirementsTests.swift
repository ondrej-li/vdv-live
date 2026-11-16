import XCTest

/// Guards the two things a submission needs from the bundle itself.
///
/// Both are invisible until an upload is refused, which is the worst place to
/// find out: the privacy manifest is checked by the upload pipeline, not by the
/// app, so nothing else in the test suite would notice it going missing.
final class AppStoreRequirementsTests: XCTestCase {
    /// `PrivacyInfo.xcprivacy` is required for any app that uses a required
    /// reason API, and the app reads and writes its own `UserDefaults`.
    func testTheBundleShipsAPrivacyManifest() throws {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            "PrivacyInfo.xcprivacy is not in the app bundle, so an upload would be rejected"
        )
        XCTAssertFalse(try Data(contentsOf: url).isEmpty)
    }

    /// The manifest is only worth shipping if it declares what the app actually
    /// uses: the defaults reason, and that nothing is tracked.
    func testTheManifestDeclaresTheDefaultsReasonAndNoTracking() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let plist = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: url),
            format: nil
        )
        let root = try XCTUnwrap(plist as? [String: Any])

        let types = try XCTUnwrap(
            root["NSPrivacyAccessedAPITypes"] as? [[String: Any]],
            "the manifest declares no accessed API types"
        )
        let defaults = try XCTUnwrap(
            types.first { $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults" },
            "UserDefaults is used, so the manifest has to declare it"
        )
        let reasons = try XCTUnwrap(defaults["NSPrivacyAccessedAPITypeReasons"] as? [String])
        XCTAssertTrue(reasons.contains("CA92.1"), "CA92.1 is the reason for an app's own defaults")

        XCTAssertEqual(root["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((root["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0)
    }

    /// The app, the watch app and the widget extension have to carry the same
    /// version and the same build number.
    ///
    /// A release means editing `MARKETING_VERSION` in five places, and forgetting
    /// one is invisible until App Store Connect refuses the upload or TestFlight
    /// offers a build whose number disagrees with itself. This is the check that a
    /// version bump is complete rather than partial.
    func testEveryBundleInTheAppCarriesTheSameVersion() throws {
        let app = Bundle.main
        let short = try XCTUnwrap(app.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        let build = try XCTUnwrap(app.object(forInfoDictionaryKey: "CFBundleVersion") as? String)

        let embedded = embeddedBundles()
        XCTAssertEqual(embedded.count, 2, "the watch app and the widget extension ship inside the app")

        for bundle in embedded {
            let name = bundle.bundleURL.lastPathComponent
            XCTAssertEqual(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                           short,
                           "\(name) carries a different marketing version")
            XCTAssertEqual(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
                           build,
                           "\(name) carries a different build number")
        }
    }

    /// The two bundles the app embeds: the watch app and the widget extension.
    private func embeddedBundles() -> [Bundle] {
        let root = Bundle.main.bundleURL
        return [
            root.appendingPathComponent("PlugIns/VdvLiveWidgets.appex"),
            root.appendingPathComponent("Watch/VdvLive Watch.app")
        ].compactMap { Bundle(url: $0) }
    }

    /// The export compliance question comes up on every upload unless the bundle
    /// answers it, and the app uses only the system's own HTTPS.
    func testTheBundleAnswersTheExportComplianceQuestion() throws {
        let value = Bundle.main.object(forInfoDictionaryKey: "ITSAppUsesNonExemptEncryption")

        XCTAssertEqual(value as? Bool, false)
    }
}
