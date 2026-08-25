import Foundation
import XCTest
@testable import OffRentDomain

/// `Use 0 values` must not come back.
///
/// A screenshot showed a residential lease — correctly recognised as containing nothing about an
/// equipment rental — under a large orange button reading `Use 0 values`. The button was doing
/// the honest thing and committing nothing, while looking like the way forward.
final class ScanOutcomeTests: XCTestCase {

    private func suggestion(_ field: SuggestedField, confidence: Double = 0.9) -> FieldSuggestion {
        FieldSuggestion(
            field: field,
            value: .text("x"),
            confidence: confidence,
            provenance: SuggestionProvenance(
                sourceLine: "x", lineIndex: 0, rule: "test", recognitionConfidence: 1
            )
        )
    }

    // MARK: - What counts as usable

    func testNoSuggestionsIsNothingFound() {
        XCTAssertEqual(ScanOutcome.evaluate(suggestions: [], kind: .rentalContract), .nothingFound)
    }

    func testInvoiceFieldsOnAContractDoNotCountAsRentalDetails() {
        // A rate table read off a contract is useful; an "invoice total" is not something a
        // rental agreement carries, so finding one is not a reason to offer the commit button.
        let outcome = ScanOutcome.evaluate(
            suggestions: [suggestion(.invoiceTotal), suggestion(.taxAmount)],
            kind: .rentalContract
        )
        XCTAssertEqual(outcome, .nothingFound)
    }

    func testContractDatesOnAnInvoiceDoNotCount() {
        let outcome = ScanOutcome.evaluate(
            suggestions: [suggestion(.startDate), suggestion(.scheduledEndDate)],
            kind: .vendorInvoice
        )
        XCTAssertEqual(outcome, .nothingFound)
    }

    func testSharedFieldsCountOnBothKinds() {
        for kind in DocumentKind.allCases {
            XCTAssertEqual(
                ScanOutcome.evaluate(suggestions: [suggestion(.vendorName)], kind: kind),
                .found(count: 1)
            )
        }
    }

    func testTheCountIsWhatWasFoundNotWhatIsTicked() {
        let outcome = ScanOutcome.evaluate(
            suggestions: [
                suggestion(.equipmentName), suggestion(.dailyRate, confidence: 0.2),
                suggestion(.serialNumber),
            ],
            kind: .rentalContract
        )
        XCTAssertEqual(outcome, .found(count: 3))
        XCTAssertTrue(outcome.hasAnything)
    }

    // MARK: - The words on the button

    func testTheCommitButtonRefusesToRenderAZero() {
        XCTAssertNil(ScanReviewCopy.useValues(selected: 0))
        XCTAssertNil(ScanReviewCopy.useValues(selected: -1))
    }

    func testTheCommitButtonCountsAndAgreesWithItself() {
        XCTAssertEqual(ScanReviewCopy.useValues(selected: 1), "Use 1 suggested value")
        XCTAssertEqual(ScanReviewCopy.useValues(selected: 7), "Use 7 suggested values")
    }

    func testTheEmptyStateNamesWhatWasNotFoundAndOffersThreeWaysOn() {
        XCTAssertEqual(
            ScanReviewCopy.nothingFoundTitle(kind: .rentalContract), "No rental details found"
        )
        XCTAssertEqual(
            ScanReviewCopy.nothingFoundTitle(kind: .vendorInvoice), "No invoice details found"
        )
        XCTAssertFalse(ScanReviewCopy.rescan.isEmpty)
        XCTAssertFalse(ScanReviewCopy.addPages.isEmpty)
        XCTAssertFalse(ScanReviewCopy.enterManually.isEmpty)
    }

    func testTheEmptyStateSaysTheTextWasReadRatherThanThatScanningFailed() {
        // The distinction matters: OCR worked, the document simply is not a rental agreement.
        let message = ScanReviewCopy.nothingFoundMessage(kind: .rentalContract, pageCount: 3)
        XCTAssertTrue(message.contains("was read"), message)
        XCTAssertTrue(message.contains("those 3 pages"), message)
    }

    func testTheSummaryNeverSaysZeroValues() {
        for pageCount in 1...4 {
            let empty = ScanReviewCopy.summary(outcome: .nothingFound, pageCount: pageCount)
            XCTAssertFalse(empty.contains("0 value"), empty)
        }
        XCTAssertTrue(
            ScanReviewCopy.summary(outcome: .found(count: 1), pageCount: 1).contains("1 value")
        )
        XCTAssertTrue(
            ScanReviewCopy.summary(outcome: .found(count: 6), pageCount: 2)
                .contains("6 values across 2 pages")
        )
    }
}

/// Page attribution on a recognised document.
final class RecognizedDocumentPageTests: XCTestCase {

    func testALineKnowsWhichPageItCameFrom() {
        let document = RecognizedDocument(
            rawText: "a\nb\nc",
            lines: ["a", "b", "c"],
            linePages: [0, 1, 1],
            pageCount: 2
        )
        XCTAssertEqual(document.page(ofLineAt: 0), 0)
        XCTAssertEqual(document.page(ofLineAt: 2), 1)
        XCTAssertEqual(document.lines(onPage: 1).map(\.text), ["b", "c"])
    }

    func testADocumentWithNoPageAttributionReportsPageZeroRatherThanCrashing() {
        let document = RecognizedDocument(rawText: "a\nb")
        XCTAssertEqual(document.page(ofLineAt: 0), 0)
        XCTAssertEqual(document.page(ofLineAt: 99), 0)
    }

    func testProvenanceOnlyNamesAPageWhenThereIsMoreThanOne() {
        let provenance = SuggestionProvenance(
            sourceLine: "TOTAL DUE $3,214.00",
            lineIndex: 40,
            rule: "labelled-invoice-total",
            recognitionConfidence: 0.98,
            page: 3
        )
        XCTAssertNil(provenance.pageDescription(of: 1))
        XCTAssertEqual(provenance.pageDescription(of: 5), "page 4")
    }
}
