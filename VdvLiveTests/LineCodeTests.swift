import XCTest
@testable import VdvLive

final class LineCodeTests: XCTestCase {
    func testSplitsTheOperatorPrefixFromTheLine() {
        let code = LineCode(raw: "764337")

        XCTAssertEqual(code.operatorCode, "764")
        XCTAssertEqual(code.number, "337")
        XCTAssertEqual(code.displayText, "337")
        XCTAssertEqual(code.fullText, "764337")
    }

    func testTreatsShortCodesAsTheLineItself() {
        XCTAssertNil(LineCode(raw: "301").operatorCode)
        XCTAssertEqual(LineCode(raw: "301").number, "301")

        // Train numbers are four to seven digits and carry no operator prefix.
        XCTAssertNil(LineCode(raw: "5907").operatorCode)
        XCTAssertEqual(LineCode(raw: "5907").number, "5907")
        XCTAssertNil(LineCode(raw: "5435405").operatorCode)
        XCTAssertEqual(LineCode(raw: "5435405").number, "5435405")
    }

    func testTrimsSurroundingWhitespace() {
        XCTAssertEqual(LineCode(raw: " 764337 ").number, "337")
        XCTAssertEqual(LineCode(raw: " 764337 ").fullText, "764337")
    }

    func testStripsLeadingZerosFromTheLineNumber() {
        XCTAssertEqual(LineCode(raw: "680036").number, "36")
        XCTAssertEqual(LineCode(raw: "680036").operatorCode, "680")
        XCTAssertEqual(LineCode(raw: "680000").number, "0")
    }

    func testMatchesALineWhetherOrNotTheOperatorIsWritten() {
        XCTAssertTrue(LineCode(raw: "764337").matches(LineCode(raw: "337")))
        XCTAssertTrue(LineCode(raw: "337").matches(LineCode(raw: "764337")))
        XCTAssertFalse(LineCode(raw: "764337").matches(LineCode(raw: "764420")))
    }

    func testLeavesAlphanumericCodesAlone() {
        let code = LineCode(raw: "X1")

        XCTAssertNil(code.operatorCode)
        XCTAssertEqual(code.number, "X1")
    }
}

final class HTMLEntitiesTests: XCTestCase {
    func testDecodesHexadecimalReferences() {
        XCTAssertEqual(
            HTMLEntities.decode("Tel&#x10D;,Hradeck&#xE1; &#x161;kola"),
            "Telč,Hradecká škola"
        )
    }

    func testDecodesDecimalReferencesAndNamedOnes() {
        XCTAssertEqual(HTMLEntities.decode("A&#269;B&amp;C&lt;D&#39;E"), "AčB&C<D'E")
    }

    func testLeavesTextWithoutEntitiesAlone() {
        XCTAssertEqual(HTMLEntities.decode("Jihlava,aut.nádr."), "Jihlava,aut.nádr.")
    }

    func testKeepsBrokenReferencesVerbatim() {
        XCTAssertEqual(HTMLEntities.decode("100&#xZZ;"), "100&#xZZ;")
    }
}
