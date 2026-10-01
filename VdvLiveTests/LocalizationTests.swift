import XCTest
@testable import VdvLive

/// Checks that the interface really is translated, and that counted strings use
/// the right plural form.
///
/// Each language is looked up in its own compiled `.lproj`, so the assertions
/// say what a Czech phone would see whatever language the test host runs in.
final class LocalizationTests: XCTestCase {
    private let czech = Locale(identifier: "cs")
    private let english = Locale(identifier: "en")

    private func bundle(for language: String) throws -> Bundle {
        let path = try XCTUnwrap(
            Bundle.main.path(forResource: language, ofType: "lproj"),
            "No \(language).lproj in the app bundle"
        )
        return try XCTUnwrap(Bundle(path: path))
    }

    private func czechString(_ key: String) throws -> String {
        String(localized: String.LocalizationValue(key), bundle: try bundle(for: "cs"), locale: czech)
    }

    private func englishString(_ key: String) throws -> String {
        String(localized: String.LocalizationValue(key), bundle: try bundle(for: "en"), locale: english)
    }

    func testTheBundleShipsBothLanguages() {
        XCTAssertTrue(Bundle.main.localizations.contains("cs"))
        XCTAssertTrue(Bundle.main.localizations.contains("en"))
    }

    func testEnglishStaysTheSourceLanguage() throws {
        XCTAssertEqual(try englishString("Bus"), "Bus")
        XCTAssertEqual(try englishString("Last stop"), "Last stop")
        XCTAssertEqual(try englishString("Next stop"), "Next stop")
        XCTAssertEqual(try englishString("Settings"), "Settings")
    }

    func testTranslatesTheMapInterfaceIntoCzech() throws {
        XCTAssertEqual(try czechString("Vysočina"), "Vysočina")
        XCTAssertEqual(try czechString("All"), "Vše")
        XCTAssertEqual(try czechString("Pinned"), "Oblíbené")
        XCTAssertEqual(try czechString("Bus"), "Autobus")
        XCTAssertEqual(try czechString("Trolleybus"), "Trolejbus")
        XCTAssertEqual(try czechString("Tram"), "Tramvaj")
        XCTAssertEqual(try czechString("Train"), "Vlak")
        XCTAssertEqual(try czechString("Ferry"), "Přívoz")
        XCTAssertEqual(try czechString("Unknown"), "Neznámé")
        XCTAssertEqual(try czechString("on time"), "včas")
        XCTAssertEqual(try czechString("no data"), "bez dat")
        XCTAssertEqual(try czechString("Open the map here from now on"), "Otevírat mapu vždy tady")
        XCTAssertEqual(try czechString("Stop opening the map here"), "Neotvírat mapu tady")
    }

    func testTranslatesTheDetailCardIntoCzech() throws {
        XCTAssertEqual(try czechString("Service"), "Spoj")
        XCTAssertEqual(try czechString("Last stop"), "Poslední zastávka")
        XCTAssertEqual(try czechString("Next stop"), "Další zastávka")
        XCTAssertEqual(
            try czechString("Timetable for this service is not available."),
            "Jízdní řád pro tento spoj není k dispozici."
        )
        XCTAssertEqual(try czechString("Barrier-free"), "Bezbariérový")
        XCTAssertEqual(try czechString("Line %@"), "Linka %@")
        XCTAssertEqual(try czechString("operator %@"), "dopravce %@")
        XCTAssertEqual(try czechString("delay %@"), "zpoždění %@")
    }

    func testTranslatesTheSettingsScreenIntoCzech() throws {
        XCTAssertEqual(try czechString("Settings"), "Nastavení")
        XCTAssertEqual(try czechString("Refresh"), "Aktualizace")
        XCTAssertEqual(try czechString("Automatic refresh"), "Automatická aktualizace")
        XCTAssertEqual(try czechString("Refresh interval"), "Interval aktualizace")
        XCTAssertEqual(try czechString("Language"), "Jazyk")
        XCTAssertEqual(try czechString("System"), "Systémové")
        XCTAssertEqual(try czechString("Done"), "Hotovo")
        XCTAssertEqual(try czechString("Open at my location"), "Otevřít na mé poloze")
        XCTAssertEqual(try czechString("My location"), "Moje poloha")
        XCTAssertEqual(try czechString("Show my position on the map"), "Zobrazit moji polohu na mapě")
        XCTAssertEqual(try czechString("Follow my position"), "Sledovat moji polohu")
        XCTAssertEqual(try czechString("Stop following my position"), "Přestat sledovat moji polohu")
        XCTAssertEqual(try czechString("Clear saved view"), "Zrušit uložený výřez")
        XCTAssertEqual(try czechString("Vehicles"), "Vozidla")
        XCTAssertEqual(try czechString("Group buses within"), "Seskupovat autobusy blíž než")
        XCTAssertEqual(try czechString("Off"), "Vypnuto")
        XCTAssertEqual(try czechString("Preferences"), "Předvolby")
        XCTAssertEqual(try czechString("Acknowledgements"), "Poděkování")
        XCTAssertEqual(try czechString("Where the data comes from"), "Odkud pocházejí data")
        XCTAssertEqual(try czechString("Live vehicle positions"), "Polohy vozidel v reálném čase")
        XCTAssertEqual(try czechString("The app"), "Aplikace")
        XCTAssertEqual(
            try czechString("VDV Live is written and maintained by Ondrej Linek."),
            "VDV Live vyvíjí a spravuje Ondrej Linek."
        )
        XCTAssertEqual(
            try czechString("Feedback, bug reports and feature requests are welcome there."),
            "Zpětná vazba, hlášení chyb a nápady na nové funkce jsou vítány právě tam."
        )
    }

    func testTranslatesTheTimetableScreenIntoCzech() throws {
        XCTAssertEqual(try czechString("Timetables"), "Jízdní řády")
        XCTAssertEqual(try czechString("Download timetables"), "Stáhnout jízdní řády")
        XCTAssertEqual(try czechString("Download again"), "Stáhnout znovu")
        XCTAssertEqual(try czechString("Published"), "Zveřejněno")
        XCTAssertEqual(try czechString("Check for updates"), "Zkontrolovat aktualizace")
        XCTAssertEqual(try czechString("Checking for updates…"), "Kontroluji aktualizace…")
        XCTAssertEqual(try czechString("Update now"), "Aktualizovat")
        XCTAssertEqual(try czechString("Up to date."), "Aktuální.")
        XCTAssertEqual(try czechString("A newer archive is published."), "Je zveřejněn novější archiv.")
        XCTAssertEqual(
            try czechString("This index does not record which archive it came from."),
            "Index neuvádí, ze kterého archivu pochází."
        )
        XCTAssertEqual(try czechString("Remove"), "Odebrat")
    }

    func testTranslatesTheBannersIntoCzech() throws {
        XCTAssertEqual(
            try czechString("The feed is not reporting any vehicles at the moment."),
            "Zdroj dat momentálně nehlásí žádná vozidla."
        )
        XCTAssertEqual(
            try czechString("None of your pinned lines are running right now."),
            "Z vašich oblíbených linek momentálně nic nejede."
        )
        XCTAssertEqual(
            try czechString("There is no internet connection."),
            "Chybí připojení k internetu."
        )
    }

    func testCountedVehiclesUseCzechPluralForms() throws {
        let forms = try pluralForms(for: "%lld vehicles", in: "cs")

        XCTAssertEqual(forms["one"], "%lld vozidlo")
        XCTAssertEqual(forms["few"], "%lld vozidla")
        XCTAssertEqual(forms["other"], "%lld vozidel")
    }

    func testCountedVehiclesUseEnglishPluralForms() throws {
        let forms = try pluralForms(for: "%lld vehicles", in: "en")

        XCTAssertEqual(forms["one"], "%lld vehicle")
        XCTAssertEqual(forms["other"], "%lld vehicles")
    }

    /// Counted strings are looked up through the plural table rather than by
    /// formatting them: which form a number picks depends on the language the
    /// *process* runs in, and a test host's language is not a thing to depend on.
    private func pluralForms(for key: String, in language: String) throws -> [String: String] {
        let path = try XCTUnwrap(
            try bundle(for: language).path(forResource: "Localizable", ofType: "stringsdict"),
            "No plural table for \(language)"
        )
        let table = try XCTUnwrap(
            NSDictionary(contentsOfFile: path) as? [String: Any],
            "Could not read the plural table for \(language)"
        )
        let entry = try XCTUnwrap(table[key] as? [String: Any], "No plural entry for \(key)")

        let categories: Set<String> = ["zero", "one", "two", "few", "many", "other"]
        for (name, value) in entry where name != "NSStringLocalizedFormatKey" {
            guard let forms = value as? [String: Any] else { continue }
            let known = forms.filter { categories.contains($0.key) }
            if !known.isEmpty {
                return known.compactMapValues { $0 as? String }
            }
        }
        return [:]
    }

    func testPinnedCountsAreTranslatedInBothLanguages() throws {
        XCTAssertEqual(
            String(format: try czechString("Pinned (%lld)"), 2),
            "Oblíbené (2)"
        )
        XCTAssertEqual(
            String(format: try englishString("Pinned (%lld)"), 2),
            "Pinned (2)"
        )
    }

    func testOperatorSuffixIsTranslated() throws {
        XCTAssertEqual(
            String(format: try czechString("%@ · operator %@"), "Autobus", "764"),
            "Autobus · dopravce 764"
        )
        XCTAssertEqual(
            String(format: try englishString("%@ · operator %@"), "Bus", "764"),
            "Bus · operator 764"
        )
    }

    func testScaleLegendIsTranslated() throws {
        XCTAssertEqual(try czechString("Map scale"), "Měřítko mapy")
        XCTAssertEqual(String(format: try czechString("%lld m"), 200), "200 m")
        XCTAssertEqual(String(format: try czechString("%lld km"), 5), "5 km")
        XCTAssertEqual(String(format: try englishString("%lld km"), 5), "5 km")
    }
}
