import Foundation
import XCTest
@testable import OffRentDomain

/// The OCR parser, exercised against synthetic fixtures with no camera, no simulator and no
/// image decoding anywhere in the path.
final class DocumentTextParserTests: XCTestCase {

    // MARK: - Fixture loading

    /// Fixtures live once, in the app's resource folder, and are read from disk relative to this
    /// file. Duplicating them into the test bundle would let the two copies drift, and the copy
    /// the app ships is the one worth testing.
    private func fixture(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // OffRentDomainTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let url = root
            .appendingPathComponent("OffRentLedger/Resources/OCRFixtures")
            .appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func document(
        _ name: String, confidence: Double = 1.0, source: DocumentSource = .documentCamera
    ) throws -> RecognizedDocument {
        RecognizedDocument(
            rawText: try fixture(name),
            averageRecognitionConfidence: confidence,
            source: source
        )
    }

    private func parse(
        _ name: String, kind: DocumentKind, confidence: Double = 1.0
    ) throws -> ParseResult {
        DocumentTextParser.parse(
            try document(name, confidence: confidence), kind: kind, calendar: calendar()
        )
    }

    func testEveryFixtureIsPresent() throws {
        for name in [
            "contract_skidsteer_clean.txt", "contract_excavator_messy.txt",
            "contract_minimal.txt", "invoice_matching.txt", "invoice_extra_day.txt",
            "invoice_with_fees.txt", "invoice_noisy_lowconf.txt",
        ] {
            XCTAssertFalse(try fixture(name).isEmpty, name)
        }
    }

    // MARK: - Contracts

    func testCleanContractParsesEveryLabelledField() throws {
        let result = try parse("contract_skidsteer_clean.txt", kind: .rentalContract)

        XCTAssertEqual(result.suggestion(for: .agreementNumber)?.value, .text("CR-44821"))
        XCTAssertEqual(result.suggestion(for: .equipmentIdentifier)?.value, .text("SS-2214"))
        XCTAssertEqual(result.suggestion(for: .serialNumber)?.value, .text("A9KT4417732"))
        XCTAssertEqual(
            result.suggestion(for: .equipmentName)?.value,
            .text("Skid Steer Loader 75HP Closed Cab")
        )
        XCTAssertEqual(result.suggestion(for: .startDate)?.value, .date(date(2026, 5, 4, 12)))
        XCTAssertEqual(result.suggestion(for: .scheduledEndDate)?.value, .date(date(2026, 5, 18, 12)))
    }

    func testDayLabelledWeeklyAndFourWeekRatesAreNotReadAsDailyRates() throws {
        // "7 DAY RATE: $985.00" and "4 WEEK RATE: $2,450.00" sit directly under
        // "DAILY RATE: $285.00". Reading either as the daily rate would inflate every estimate
        // this app produces by three to eight times.
        let result = try parse("contract_skidsteer_clean.txt", kind: .rentalContract)
        XCTAssertEqual(result.suggestion(for: .dailyRate)?.value, .money(money("285.00")))
        XCTAssertEqual(result.suggestion(for: .weeklyRate)?.value, .money(money("985.00")))
        XCTAssertEqual(result.suggestion(for: .fourWeekRate)?.value, .money(money("2450.00")))
    }

    func testTwentyEightDayAndWeeklyLabelsAreDistinguished() throws {
        let result = try parse("contract_excavator_messy.txt", kind: .rentalContract)
        XCTAssertEqual(result.suggestion(for: .dailyRate)?.value, .money(money("410.00")))
        XCTAssertEqual(result.suggestion(for: .weeklyRate)?.value, .money(money("1375.00")))
        XCTAssertEqual(result.suggestion(for: .fourWeekRate)?.value, .money(money("3890.00")))
    }

    func testSpaceBeforeColonAndBareLabelsStillParse() throws {
        let result = try parse("contract_excavator_messy.txt", kind: .rentalContract)
        XCTAssertEqual(result.suggestion(for: .agreementNumber)?.value, .text("TM-9013-B"))
        XCTAssertEqual(result.suggestion(for: .equipmentIdentifier)?.value, .text("EX-0431"))
        XCTAssertEqual(result.suggestion(for: .startDate)?.value, .date(date(2026, 11, 29, 12)))
        XCTAssertEqual(result.suggestion(for: .scheduledEndDate)?.value, .date(date(2026, 12, 13, 12)))
    }

    func testUnparseableDocumentYieldsNothingRatherThanGuesses() throws {
        let result = try parse("contract_minimal.txt", kind: .rentalContract)
        XCTAssertTrue(
            result.suggestions.isEmpty,
            "a handwritten note must produce no suggestions at all, not low-confidence noise"
        )
        XCTAssertEqual(result.unmatchedLines.count, 3)
    }

    // MARK: - Vendor letterhead

    func testVendorNameIsGuessedFromTheLetterheadButNeverPreselected() throws {
        let result = try parse("contract_skidsteer_clean.txt", kind: .rentalContract)
        let vendor = try XCTUnwrap(result.suggestion(for: .vendorName))
        XCTAssertEqual(vendor.value, .text("CEDAR RIDGE EQUIPMENT RENTAL LLC"))
        XCTAssertEqual(vendor.provenance.rule, "letterhead-position-guess")
        XCTAssertFalse(
            vendor.isPreselected,
            "a layout guess must never arrive already ticked, even on a perfect scan"
        )
    }

    func testAddressLinesAreNotMistakenForTheVendorName() throws {
        let result = try parse("contract_skidsteer_clean.txt", kind: .rentalContract)
        let vendor = result.suggestion(for: .vendorName)
        XCTAssertNotEqual(vendor?.value, .text("4820 Foundry Road, Bay 3"))
        XCTAssertNotEqual(vendor?.value, .text("(940) 555-0148"))
    }

    // MARK: - Invoices

    func testMatchingInvoiceParses() throws {
        let result = try parse("invoice_matching.txt", kind: .vendorInvoice)
        XCTAssertEqual(result.suggestion(for: .invoiceNumber)?.value, .text("INV-88213"))
        XCTAssertEqual(result.suggestion(for: .agreementNumber)?.value, .text("CR-44821"))
        XCTAssertEqual(result.suggestion(for: .billedThroughDate)?.value, .date(date(2026, 5, 11, 12)))
        XCTAssertEqual(result.suggestion(for: .rentalSubtotal)?.value, .money(money("2280.00")))
        XCTAssertEqual(result.suggestion(for: .deliveryCharge)?.value, .money(money("150.00")))
        XCTAssertEqual(result.suggestion(for: .taxAmount)?.value, .money(money("200.48")))
        XCTAssertEqual(result.suggestion(for: .invoiceTotal)?.value, .money(money("2630.48")))
    }

    func testAmountDueIsReadAsTheInvoiceTotal() throws {
        let result = try parse("invoice_extra_day.txt", kind: .vendorInvoice)
        XCTAssertEqual(result.suggestion(for: .invoiceTotal)?.value, .money(money("2939.99")))
        XCTAssertEqual(result.suggestion(for: .rentalSubtotal)?.value, .money(money("2565.00")))
    }

    func testEveryFeeCategoryIsRecognisedSeparately() throws {
        let result = try parse("invoice_with_fees.txt", kind: .vendorInvoice)
        XCTAssertEqual(result.suggestion(for: .rentalSubtotal)?.value, .money(money("5504.00")))
        XCTAssertEqual(result.suggestion(for: .deliveryCharge)?.value, .money(money("225.00")))
        XCTAssertEqual(result.suggestion(for: .pickupCharge)?.value, .money(money("225.00")))
        XCTAssertEqual(result.suggestion(for: .fuelCharge)?.value, .money(money("148.60")))
        XCTAssertEqual(result.suggestion(for: .cleaningCharge)?.value, .money(money("95.00")))
        XCTAssertEqual(result.suggestion(for: .damageCharge)?.value, .money(money("412.80")))
        XCTAssertEqual(result.suggestion(for: .environmentalCharge)?.value, .money(money("38.00")))
        XCTAssertEqual(result.suggestion(for: .taxAmount)?.value, .money(money("549.32")))
        XCTAssertEqual(result.suggestion(for: .invoiceTotal)?.value, .money(money("7197.72")))
    }

    func testEveryChargeSuggestionMapsToAnInvoiceCategory() throws {
        let result = try parse("invoice_with_fees.txt", kind: .vendorInvoice)
        let charges = result.suggestions.filter { $0.field.invoiceCategory != nil }
        XCTAssertEqual(charges.count, 8)
        XCTAssertEqual(
            Set(charges.compactMap { $0.field.invoiceCategory }).count, 8,
            "each charge field must map to a distinct category"
        )
    }

    func testContractRulesDoNotFireOnInvoiceFieldsAndViceVersa() throws {
        let contract = try parse("contract_skidsteer_clean.txt", kind: .rentalContract)
        XCTAssertNil(contract.suggestion(for: .invoiceTotal))
        XCTAssertNil(contract.suggestion(for: .taxAmount))

        let invoice = try parse("invoice_matching.txt", kind: .vendorInvoice)
        XCTAssertNil(invoice.suggestion(for: .startDate))
    }

    // MARK: - Confidence

    func testHighConfidenceLabelledFieldsArePreselectedOnACleanScan() throws {
        let result = try parse("invoice_matching.txt", kind: .vendorInvoice)
        let labelled = result.suggestions.filter { $0.provenance.rule != "letterhead-position-guess" }
        XCTAssertFalse(labelled.isEmpty)
        for suggestion in labelled {
            XCTAssertTrue(
                suggestion.isPreselected,
                "\(suggestion.field) at \(suggestion.confidence) should be preselected on a clean scan"
            )
        }
    }

    func testAMarginalScanPreselectsNothing() throws {
        // The same labelled fields, from a recogniser that is only 55% sure of the characters.
        let result = try parse("invoice_noisy_lowconf.txt", kind: .vendorInvoice, confidence: 0.55)
        XCTAssertFalse(result.suggestions.isEmpty, "it should still read what it can")
        XCTAssertTrue(
            result.preselected.isEmpty,
            "nothing may arrive ticked when the recogniser itself is unsure"
        )
    }

    func testConfidenceDegradesMonotonicallyWithRecognitionQuality() throws {
        var previous = 1.1
        for quality in [1.0, 0.9, 0.7, 0.5, 0.2] {
            let result = try parse("invoice_matching.txt", kind: .vendorInvoice, confidence: quality)
            let total = try XCTUnwrap(result.suggestion(for: .invoiceTotal))
            XCTAssertLessThan(total.confidence, previous)
            previous = total.confidence
        }
    }

    func testConfidenceIsAlwaysWithinZeroAndOne() throws {
        for quality in [0.0, 0.3, 1.0] {
            let result = try parse("invoice_with_fees.txt", kind: .vendorInvoice, confidence: quality)
            for suggestion in result.suggestions {
                XCTAssertGreaterThanOrEqual(suggestion.confidence, 0.0)
                XCTAssertLessThanOrEqual(suggestion.confidence, 1.0)
            }
        }
    }

    // MARK: - Provenance

    func testEverySuggestionCarriesTheLineItWasReadFrom() throws {
        let result = try parse("invoice_with_fees.txt", kind: .vendorInvoice)
        let document = try self.document("invoice_with_fees.txt")
        for suggestion in result.suggestions {
            XCTAssertFalse(suggestion.provenance.sourceLine.isEmpty, "\(suggestion.field)")
            XCTAssertFalse(suggestion.provenance.rule.isEmpty, "\(suggestion.field)")
            XCTAssertTrue(
                document.lines.indices.contains(suggestion.provenance.lineIndex),
                "\(suggestion.field) points outside the document"
            )
            XCTAssertEqual(
                document.lines[suggestion.provenance.lineIndex],
                suggestion.provenance.sourceLine
            )
        }
    }

    func testRawTextIsPreservedSeparatelyFromInterpretation() throws {
        let result = try parse("contract_skidsteer_clean.txt", kind: .rentalContract)
        XCTAssertTrue(result.rawText.contains("Excess hours billed at 1/8 of day rate."))
        XCTAssertFalse(
            result.suggestions.contains { $0.value.textValue?.contains("Excess hours") ?? false },
            "prose the parser does not understand stays in the raw text, not in a field"
        )
    }

    func testUnmatchedLinesAreReportedSoTheUserSeesWhatWasSkipped() throws {
        let result = try parse("contract_skidsteer_clean.txt", kind: .rentalContract)
        XCTAssertTrue(result.unmatchedLines.contains { $0.contains("Renter is responsible") })
    }

    // MARK: - Determinism

    func testParsingIsDeterministic() throws {
        let document = try self.document("invoice_with_fees.txt")
        let first = DocumentTextParser.parse(document, kind: .vendorInvoice, calendar: calendar())
        for _ in 0..<25 {
            let again = DocumentTextParser.parse(document, kind: .vendorInvoice, calendar: calendar())
            XCTAssertEqual(
                first.suggestions.map { [$0.field.rawValue, "\($0.value)", "\($0.confidence)"] },
                again.suggestions.map { [$0.field.rawValue, "\($0.value)", "\($0.confidence)"] }
            )
        }
    }

    func testSuggestionOrderIsStable() throws {
        let result = try parse("invoice_with_fees.txt", kind: .vendorInvoice)
        XCTAssertEqual(
            result.suggestions.map(\.field.rawValue),
            result.suggestions.map(\.field.rawValue).sorted()
        )
    }
}

final class DateTextParserTests: XCTestCase {

    func testCommonUSRentalPaperworkFormats() {
        let cases: [(String, Date)] = [
            ("05/04/2026", date(2026, 5, 4, 12)),
            ("5/4/2026", date(2026, 5, 4, 12)),
            ("05/04/26", date(2026, 5, 4, 12)),
            ("05-04-2026", date(2026, 5, 4, 12)),
            ("2026-05-04", date(2026, 5, 4, 12)),
            ("May 4, 2026", date(2026, 5, 4, 12)),
            ("Mav 4, 2026", date(2026, 5, 4, 12)),  // sanity: must FAIL, checked below
        ]
        for (text, expected) in cases.dropLast() {
            XCTAssertEqual(DateTextParser.parse(text, calendar: calendar()), expected, text)
        }
        XCTAssertNil(DateTextParser.parse("Mav 4, 2026", calendar: calendar()))
    }

    func testDatesAreAnchoredAtNoonSoTimeZoneShiftsCannotMoveTheDay() {
        // A date stored at midnight is the previous day one time zone west. On a rental start
        // date that is a billing dispute the app itself caused.
        let parsed = try? XCTUnwrap(DateTextParser.parse("05/04/2026", calendar: calendar()))
        let hour = calendar().component(.hour, from: parsed ?? Date())
        XCTAssertEqual(hour, 12)
    }

    func testImplausibleYearsAreRejected() {
        XCTAssertNil(DateTextParser.parse("05/04/1904", calendar: calendar()))
        XCTAssertNil(DateTextParser.parse("05/04/2141", calendar: calendar()))
    }

    func testGarbageIsRejected() {
        for text in ["", "  ", "next tuesday", "13/45/2026", "$285.00"] {
            XCTAssertNil(DateTextParser.parse(text, calendar: calendar()), text)
        }
    }
}

final class MoneyParsingTests: XCTestCase {

    func testAcceptedForms() {
        XCTAssertEqual(MoneyMath.parse("1234.56"), money("1234.56"))
        XCTAssertEqual(MoneyMath.parse("1,234.56"), money("1234.56"))
        XCTAssertEqual(MoneyMath.parse("$1,234.56"), money("1234.56"))
        XCTAssertEqual(MoneyMath.parse(" USD 1,234.56 "), money("1234.56"))
        XCTAssertEqual(MoneyMath.parse("(45.00)"), money("-45.00"))
        XCTAssertEqual(MoneyMath.parse("-45.00"), money("-45.00"))
        XCTAssertEqual(MoneyMath.parse("0"), .zero)
    }

    func testRejectedForms() {
        // "1.200,50" is European. Guessing which separator is the decimal point on a scanned
        // invoice is how $1,200.50 becomes $1.20.
        for text in [
            "", "  ", "abc", "12.34.56", "1 234,56", "$", "--5",
            "12,34",      // European decimal comma
            "1,2345",     // malformed grouping
            "1,23,456",   // malformed grouping
            ",500",       // leading separator
            "1,234,",     // trailing separator
            ".50",        // bare decimal, ambiguous on a scan
        ] {
            XCTAssertNil(MoneyMath.parse(text), text)
        }
    }

    func testValidGroupingStillParses() {
        XCTAssertEqual(MoneyMath.parse("1,234,567.89"), money("1234567.89"))
        XCTAssertEqual(MoneyMath.parse("12,345"), money("12345"))
        XCTAssertEqual(MoneyMath.parse("999"), money("999"))
    }

    func testBankersRounding() {
        XCTAssertEqual(MoneyMath.rounded(money("2.125")), money("2.12"))
        XCTAssertEqual(MoneyMath.rounded(money("2.135")), money("2.14"))
        XCTAssertEqual(MoneyMath.rounded(money("-2.125")), money("-2.12"))
    }

    func testEqualityToTheCentIgnoresSubCentNoise() {
        XCTAssertTrue(MoneyMath.equalToTheCent(money("2280.001"), money("2280.00")))
        XCTAssertFalse(MoneyMath.equalToTheCent(money("2280.01"), money("2280.00")))
    }

    func testAbsoluteDifferenceIsNeverNegative() {
        XCTAssertEqual(MoneyMath.absoluteDifference(money("100"), money("250")), money("150"))
        XCTAssertEqual(MoneyMath.absoluteDifference(money("250"), money("100")), money("150"))
    }
}
