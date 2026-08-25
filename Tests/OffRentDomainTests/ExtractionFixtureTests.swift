import Foundation
import XCTest
@testable import OffRentDomain

/// The extraction the screenshots demanded: useful on real rental paperwork, silent on anything
/// else, and never confidently wrong about a mis-read digit.
final class ExtractionFixtureTests: XCTestCase {

    private func fixture(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: root
                .appendingPathComponent("OffRentLedger/Resources/OCRFixtures")
                .appendingPathComponent(name),
            encoding: .utf8
        )
    }

    private func parse(
        _ name: String, kind: DocumentKind, confidence: Double = 1.0, pages: Int = 1
    ) throws -> ParseResult {
        let text = try fixture(name)
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        // Page attribution built from the fixture's own page marker, so a multipage fixture
        // exercises the page-tracking path rather than only the single-page one.
        var page = 0
        var linePages: [Int] = []
        for line in lines {
            if line.hasPrefix("--- PAGE") { page += 1 }
            linePages.append(page)
        }
        return DocumentTextParser.parse(
            RecognizedDocument(
                rawText: text,
                lines: lines,
                linePages: linePages,
                averageRecognitionConfidence: confidence,
                pageCount: pages
            ),
            kind: kind,
            calendar: calendar()
        )
    }

    // MARK: - The negative test

    /// §12.12. This is the document in the screenshot that produced a `Use 0 values` button.
    func testAResidentialLeaseYieldsNoRentalFields() throws {
        let result = try parse("unrelated_residential_lease.txt", kind: .rentalContract)

        // OCR read it. The extractor found nothing, which is the correct answer.
        XCTAssertFalse(result.rawText.isEmpty, "the text must still be recognised and kept")
        XCTAssertTrue(result.rawText.contains("QUIET ENJOYMENT"))

        for field in [
            SuggestedField.equipmentName, .equipmentIdentifier, .serialNumber,
            .dailyRate, .weeklyRate, .fourWeekRate, .agreementNumber,
        ] {
            XCTAssertNil(
                result.suggestion(for: field),
                "a residential lease produced a \(field.rawValue): \(String(describing: result.suggestion(for: field)?.value))"
            )
        }
    }

    /// And the review screen therefore shows the empty state rather than a count of zero.
    func testTheLeaseProducesTheNothingFoundOutcomeRatherThanUseZeroValues() throws {
        let result = try parse("unrelated_residential_lease.txt", kind: .rentalContract)
        let outcome = ScanOutcome.evaluate(suggestions: result.suggestions, kind: .rentalContract)
        XCTAssertEqual(outcome, .nothingFound)
        XCTAssertNil(ScanReviewCopy.useValues(selected: 0))
    }

    /// A lease has dates and a company-looking letterhead. Neither may become a rental term.
    func testTheLeaseDatesAreNotReadAsRentalDates() throws {
        let result = try parse("unrelated_residential_lease.txt", kind: .rentalContract)
        XCTAssertNil(result.suggestion(for: .startDate))
        XCTAssertNil(result.suggestion(for: .scheduledEndDate))
    }

    // MARK: - A third vendor layout, with labels and values on different lines

    func testATableWithDottedLeadersAndSplitLabelsStillYieldsTheRates() throws {
        let result = try parse("contract_split_labels.txt", kind: .rentalContract)

        XCTAssertEqual(result.suggestion(for: .dailyRate)?.value, .money(money("465.00")))
        XCTAssertEqual(result.suggestion(for: .weeklyRate)?.value, .money(money("1540.00")))
        XCTAssertEqual(result.suggestion(for: .fourWeekRate)?.value, .money(money("4180.00")))
    }

    func testTheSevenDayRateIsNeverReadAsADailyRate() throws {
        // The four-fold error the whole estimate rests on not making.
        let result = try parse("contract_split_labels.txt", kind: .rentalContract)
        XCTAssertNotEqual(result.suggestion(for: .dailyRate)?.value, .money(money("1540.00")))
        XCTAssertNotEqual(result.suggestion(for: .dailyRate)?.value, .money(money("4180.00")))
    }

    func testIdentifiersSurviveALayoutTheParserHasNotSeenBefore() throws {
        let result = try parse("contract_split_labels.txt", kind: .rentalContract)
        XCTAssertEqual(result.suggestion(for: .equipmentIdentifier)?.value, .text("TH-1180"))
        XCTAssertEqual(result.suggestion(for: .serialNumber)?.value, .text("TH55K0092214"))
        XCTAssertEqual(result.suggestion(for: .agreementNumber)?.value, .text("NG-77304"))
    }

    func testAMonthNameDateFormatParses() throws {
        let result = try parse("contract_split_labels.txt", kind: .rentalContract)
        XCTAssertNotNil(result.suggestion(for: .startDate)?.value.dateValue)
        XCTAssertNotNil(result.suggestion(for: .scheduledEndDate)?.value.dateValue)
    }

    func testASplitLayoutStillFindsEnoughToBeWorthOffering() throws {
        let result = try parse("contract_split_labels.txt", kind: .rentalContract)
        guard case let .found(count) = ScanOutcome.evaluate(
            suggestions: result.suggestions, kind: .rentalContract
        ) else {
            return XCTFail("a real rental agreement must produce usable fields")
        }
        XCTAssertGreaterThanOrEqual(count, 6, "found only \(count) fields on a full agreement")
        XCTAssertEqual(ScanReviewCopy.useValues(selected: count), "Use \(count) suggested values")
    }

    // MARK: - Multipage, with the OCR digit confusion

    func testAMultipageInvoiceReportsWhichPageEachValueCameFrom() throws {
        let result = try parse("invoice_multipage_ocr_noise.txt", kind: .vendorInvoice, pages: 2)

        let number = result.suggestion(for: .invoiceNumber)
        XCTAssertEqual(number?.value, .text("NG-90551"))
        XCTAssertEqual(number?.provenance.page, 0, "the invoice number is on the first page")

        let total = result.suggestion(for: .invoiceTotal)
        XCTAssertEqual(total?.provenance.page, 1, "the total is on the second page")
        XCTAssertEqual(total?.provenance.pageDescription(of: 2), "page 2")
    }

    func testAPageIsOnlyNamedWhenThereIsMoreThanOne() throws {
        let single = try parse("invoice_matching.txt", kind: .vendorInvoice)
        let suggestion = try XCTUnwrap(single.suggestion(for: .invoiceTotal))
        XCTAssertNil(suggestion.provenance.pageDescription(of: 1))
    }

    /// `4,18O.00` — a capital O where a zero belongs. The parser must not turn that into a
    /// confident 418.00, which would understate the rental charge by an order of magnitude.
    ///
    /// Asserted unconditionally, not inside an `if let`. A conditional assertion on an optional
    /// that turns out to be nil is a test that passes by not running, which is how the first
    /// version of this one reported success while the parser was reading 418.
    func testALetterOInAnAmountIsNotSilentlyReadAsADifferentNumber() throws {
        let result = try parse("invoice_multipage_ocr_noise.txt", kind: .vendorInvoice, pages: 2)
        let subtotal = result.suggestion(for: .rentalSubtotal)?.value.moneyValue
        XCTAssertNotEqual(
            subtotal, money("418.00"),
            "an OCR letter-O became a confident amount ten times too small"
        )
        XCTAssertNil(
            subtotal,
            "a garbled amount must be refused outright rather than truncated to a plausible one"
        )
    }

    /// The tax line has the same fault — `404.O2` — and must be refused for the same reason.
    func testAGarbledDecimalIsRefusedRatherThanTruncated() throws {
        let result = try parse("invoice_multipage_ocr_noise.txt", kind: .vendorInvoice, pages: 2)
        XCTAssertNotEqual(
            result.suggestion(for: .taxAmount)?.value.moneyValue, money("404.00"),
            "404.O2 was read as 404.00"
        )
    }

    /// And a clean amount at the end of a sentence is still read. The rejection rule is about
    /// letters inside a number, not about punctuation after one.
    func testACleanAmountFollowedByAFullStopStillParses() throws {
        let document = RecognizedDocument(rawText: "TOTAL DUE: $5,292.22.")
        let result = DocumentTextParser.parse(
            document, kind: .vendorInvoice, calendar: calendar()
        )
        XCTAssertEqual(result.suggestion(for: .invoiceTotal)?.value, .money(money("5292.22")))
    }

    func testTheChargeCategoriesOnPageTwoAreEachRecognised() throws {
        let result = try parse("invoice_multipage_ocr_noise.txt", kind: .vendorInvoice, pages: 2)
        XCTAssertEqual(result.suggestion(for: .deliveryCharge)?.value, .money(money("285.00")))
        XCTAssertEqual(result.suggestion(for: .pickupCharge)?.value, .money(money("285.00")))
        XCTAssertNotNil(result.suggestion(for: .environmentalCharge))
    }

    func testEveryProvenanceCarriesTheRangeOfTheValueInItsLine() throws {
        let result = try parse("contract_skidsteer_clean.txt", kind: .rentalContract)
        for suggestion in result.suggestions where suggestion.provenance.valueStart != nil {
            let provenance = suggestion.provenance
            let start = try XCTUnwrap(provenance.valueStart)
            let length = try XCTUnwrap(provenance.valueLength)
            let line = provenance.sourceLine as NSString
            XCTAssertGreaterThanOrEqual(start, 0, provenance.sourceLine)
            XCTAssertLessThanOrEqual(
                start + length, line.length,
                "the recorded range runs past the end of “\(provenance.sourceLine)”"
            )
        }
    }

    // MARK: - Low confidence

    func testAMarginalScanOfARealAgreementStillOffersItsValuesUnticked() throws {
        let result = try parse("contract_split_labels.txt", kind: .rentalContract, confidence: 0.55)
        XCTAssertFalse(result.suggestions.isEmpty, "a marginal scan is not a blank one")
        XCTAssertTrue(
            result.preselected.isEmpty,
            "a marginal scan must tick nothing: the user's job is to check, not to notice"
        )
        XCTAssertTrue(
            ScanOutcome.evaluate(suggestions: result.suggestions, kind: .rentalContract)
                .hasAnything,
            "and the screen must still offer them rather than claiming nothing was found"
        )
    }
}
