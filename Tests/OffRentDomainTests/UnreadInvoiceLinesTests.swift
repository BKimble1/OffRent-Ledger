import Foundation
import XCTest
@testable import OffRentDomain

/// Lines the invoice parser could not interpret, salvaged so a user can enter them.
///
/// The property under test is not accuracy — it is that this never invents a charge and never
/// silently swallows one. A line offered here is only ever *offered*; a line refused here is one
/// no reasonable reader would call money.
final class UnreadInvoiceLinesTests: XCTestCase {

    // MARK: - What counts as money at the end of a line

    func testACurrencyMarkedAmountIsRead() {
        XCTAssertEqual(UnreadInvoiceLines.trailingAmount(in: "ENVIRONMENTAL FEE $42"), 42)
        XCTAssertEqual(
            UnreadInvoiceLines.trailingAmount(in: "DELIVERY TO SITE $1,250.00"),
            Decimal(string: "1250.00", locale: Locale(identifier: "en_US_POSIX"))
        )
    }

    func testAnAmountWrittenToTheCentIsReadWithoutACurrencyMark() {
        XCTAssertEqual(
            UnreadInvoiceLines.trailingAmount(in: "FUEL SURCHARGE 87.50"),
            Decimal(string: "87.50", locale: Locale(identifier: "en_US_POSIX"))
        )
    }

    func testABareIntegerIsNotReadAsMoney() {
        // "PALLET FORKS 4" is a quantity. Reading it as $4.00 would put a charge on the user's
        // invoice that the vendor never billed.
        XCTAssertNil(UnreadInvoiceLines.trailingAmount(in: "PALLET FORKS 4"))
        XCTAssertNil(UnreadInvoiceLines.trailingAmount(in: "UNIT SS-2214"))
    }

    func testAnAmbiguousCommaIsRefusedRatherThanGuessed() {
        // `12,34` is a European decimal comma. MoneyMath refuses it and so must this, because
        // being wrong turns $1,200.50 into $1.20 on a document going back to a rental yard.
        XCTAssertNil(UnreadInvoiceLines.trailingAmount(in: "TRANSPORT 12,34"))
    }

    func testZeroAndCreditsAreNotOffered() {
        XCTAssertNil(UnreadInvoiceLines.trailingAmount(in: "DAMAGE WAIVER $0.00"))
        XCTAssertNil(UnreadInvoiceLines.trailingAmount(in: "GOODWILL CREDIT ($45.00)"))
    }

    // MARK: - Which lines are offered

    func testAChargeShapedLineIsOffered() {
        let candidates = UnreadInvoiceLines.chargeCandidates(in: ["ENVIRONMENTAL RECOVERY $37.50"])
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].text, "ENVIRONMENTAL RECOVERY $37.50")
        XCTAssertEqual(
            candidates[0].amount,
            Decimal(string: "37.50", locale: Locale(identifier: "en_US_POSIX"))
        )
    }

    func testProseIsNotOfferedAsACharge() {
        let terms = """
            Renter is responsible for all damage howsoever caused during the rental period and \
            agrees to the terms printed overleaf, including the deductible of 500.00
            """
        XCTAssertTrue(UnreadInvoiceLines.chargeCandidates(in: [terms]).isEmpty)
    }

    func testABareFigureOnItsOwnLineIsNotOffered() {
        XCTAssertTrue(UnreadInvoiceLines.chargeCandidates(in: ["1,250.00", "3"]).isEmpty)
    }

    func testTheIdentifierIsThePositionInTheListItCameFrom() {
        let lines = ["PAGE 1 OF 2", "CLEANING $95.00", "THANK YOU", "TIRE REPAIR $180.00"]
        let candidates = UnreadInvoiceLines.chargeCandidates(in: lines)
        XCTAssertEqual(candidates.map(\.id), [1, 3])
        XCTAssertEqual(Set(candidates.map(\.id)).count, candidates.count)
    }

    func testSurroundingWhitespaceIsTrimmedFromWhatIsShown() {
        let candidates = UnreadInvoiceLines.chargeCandidates(in: ["   PICKUP $210.00  "])
        XCTAssertEqual(candidates.first?.text, "PICKUP $210.00")
    }

    func testNothingIsOfferedForADocumentWithNoUnmatchedLines() {
        XCTAssertTrue(UnreadInvoiceLines.chargeCandidates(in: []).isEmpty)
    }
}
