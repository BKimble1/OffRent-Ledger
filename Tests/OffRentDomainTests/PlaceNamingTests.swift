import Foundation
import XCTest
@testable import OffRentDomain

/// What a jobsite gets called.
///
/// These exist because of a shipped pin. A rural site with no street address came back from map
/// search with a placemark whose name was its ZIP code, the app took the name as given, and the
/// Today map showed a marker labelled `07820`. A postal code is an address component; nobody
/// calls a jobsite one.
final class PlaceNamingTests: XCTestCase {

    // MARK: - Recognising a code

    func testTheShippedFailureIsRecognisedAsACode() {
        XCTAssertTrue(PlaceNaming.isBarePostalCode("07820"))
    }

    func testDigitDominantAndCanadianCodesAreRecognised() {
        for code in ["07820", "07820-1234", "90210", "K1A0B1", "K1A 0B1", "75001"] {
            XCTAssertTrue(PlaceNaming.isBarePostalCode(code), code)
        }
    }

    func testUKPostcodesAreDeliberatelyNotMatched() {
        // Letter-dominant, and so is every construction site called ZONE 4 or PHASE 2. A rule
        // wide enough for `SW1A 1AA` throws those away silently, which is the worse failure.
        for code in ["SW1A 1AA", "M1 1AE"] {
            XCTAssertFalse(PlaceNaming.isBarePostalCode(code), code)
        }
    }

    func testUppercaseSiteNamesSurviveTheCodeTest() {
        for name in ["ZONE 4", "PHASE 2", "LOT 14B", "BAY 3", "SITE A2"] {
            XCTAssertFalse(PlaceNaming.isBarePostalCode(name), name)
        }
    }

    func testRealPlaceNamesAreNotMistakenForCodes() {
        let names = [
            "Cedar Ridge Equipment", "Ridgeline Business Park", "Bay 3", "Marlin Falls",
            "4820 Foundry Road", "Lot 17", "Site B", "Plano",
        ]
        for name in names {
            XCTAssertFalse(PlaceNaming.isBarePostalCode(name), name)
        }
    }

    func testAnEmptyStringIsNotACode() {
        XCTAssertFalse(PlaceNaming.isBarePostalCode(""))
        XCTAssertFalse(PlaceNaming.isBarePostalCode("   "))
    }

    // MARK: - Choosing the name

    func testABusinessNameWins() {
        let components = PlaceComponents(
            searchResultName: "Cedar Ridge Equipment Rental",
            street: "4820 Foundry Road",
            locality: "Marlin Falls",
            administrativeArea: "TX",
            postalCode: "76541"
        )
        XCTAssertEqual(PlaceNaming.suggestedSiteName(components), "Cedar Ridge Equipment Rental")
    }

    func testAPostalCodeNameFallsThroughToTheStreet() {
        // Exactly the shipped case: search returns the ZIP as the name.
        let components = PlaceComponents(
            searchResultName: "07820",
            street: "212 Quarry Lane",
            locality: "Allamuchy",
            administrativeArea: "NJ",
            postalCode: "07820"
        )
        XCTAssertEqual(PlaceNaming.suggestedSiteName(components), "212 Quarry Lane")
    }

    func testWithNoStreetItFallsThroughToTheTown() {
        let components = PlaceComponents(
            searchResultName: "07820",
            locality: "Allamuchy",
            administrativeArea: "NJ",
            postalCode: "07820"
        )
        XCTAssertEqual(PlaceNaming.suggestedSiteName(components), "Allamuchy")
    }

    func testACodeIsOnlyEverUsedAsALastResortAndIsWrittenAsOne() {
        let components = PlaceComponents(searchResultName: "07820", postalCode: "07820")
        // "Near 07820" reads as a location. "07820" reads as a mistake.
        XCTAssertEqual(PlaceNaming.suggestedSiteName(components), "Near 07820")
    }

    func testNothingAtAllStillProducesAUsableName() {
        XCTAssertEqual(PlaceNaming.suggestedSiteName(PlaceComponents()), "Dropped pin")
    }

    func testBlankFieldsAreTreatedAsAbsent() {
        let components = PlaceComponents(
            searchResultName: "   ", street: "", locality: "Marlin Falls"
        )
        XCTAssertEqual(PlaceNaming.suggestedSiteName(components), "Marlin Falls")
    }

    // MARK: - The address line

    func testTheAddressLineIsStreetThenRegion() {
        let components = PlaceComponents(
            street: "4820 Foundry Road",
            locality: "Marlin Falls",
            administrativeArea: "TX",
            postalCode: "76541"
        )
        XCTAssertEqual(
            PlaceNaming.formattedAddress(components),
            "4820 Foundry Road, Marlin Falls, TX, 76541"
        )
    }

    func testMissingPartsDoNotLeaveDanglingCommas() {
        let components = PlaceComponents(locality: "Marlin Falls", administrativeArea: "TX")
        XCTAssertEqual(PlaceNaming.formattedAddress(components), "Marlin Falls, TX")
    }

    func testAnEmptyPlaceHasNoAddressLineRatherThanAComma() {
        XCTAssertEqual(PlaceNaming.formattedAddress(PlaceComponents()), "")
    }

    func testADroppedPinIsNeverLabelledWithItsCoordinate() {
        // The rule the whole feature rests on: raw latitude and longitude are never what the
        // normal UI shows as a place.
        XCTAssertFalse(PlaceNaming.droppedPinPlaceholder.contains("."))
        XCTAssertFalse(PlaceNaming.droppedPinPlaceholder.contains(","))
        XCTAssertTrue(PlaceNaming.droppedPinPlaceholder.contains(where: \.isLetter))
    }
}
