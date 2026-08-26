import Foundation
import XCTest
@testable import OffRentDomain

/// The decision behind a button that did nothing.
///
/// The shipped failure was not that acceptance was refused — it was that "refused" and "accepted
/// with no visible effect" were indistinguishable from outside a view. A bright orange
/// `Accept this invoice` sat over an invoice whose expected amount was `Not available` and whose
/// invoiced amount was `$0.00`, and tapping it produced nothing at all.
///
/// Making the decision a value means the control can ask before it draws itself.
final class InvoiceAcceptanceTests: XCTestCase {

    private func input(
        openRecorded: Int = 0,
        unaddressed: Int = 0,
        lines: Int = 2,
        total: Decimal = 1710,
        status: InvoiceReviewStatus = .inReview
    ) -> InvoiceAcceptanceInput {
        InvoiceAcceptanceInput(
            openRecordedDiscrepancies: openRecorded,
            unaddressedFindings: unaddressed,
            lineCount: lines,
            invoiceTotal: total,
            currentStatus: status
        )
    }

    func testAnOrdinaryMatchingInvoiceCanBeAccepted() {
        XCTAssertTrue(InvoiceAcceptance.canAccept(input()))
    }

    func testTheScreenshotCaseIsBlockedWithAReasonAndARouteOut() {
        // No lines, no total: the record in the screenshot. It must not be an enabled control.
        let decision = InvoiceAcceptance.decide(input(lines: 0, total: 0))
        guard case let .failure(block) = decision else {
            return XCTFail("An invoice with nothing on it must not be acceptable")
        }
        XCTAssertEqual(block, .nothingRecorded)
        XCTAssertEqual(block.editRouteTitle, "Edit invoice")
        XCTAssertTrue(block.explanation.contains("no total and no lines"))
    }

    func testAGenuineZeroDollarInvoiceIsAcceptedRatherThanBlocked() {
        // A vendor confirming there is nothing further to pay is a real invoice with a real
        // answer, and the user is entitled to close it out.
        XCTAssertTrue(InvoiceAcceptance.canAccept(input(lines: 1, total: 0)))
    }

    func testAnInvoiceWithATotalButNoLinesIsStillAcceptable() {
        XCTAssertTrue(InvoiceAcceptance.canAccept(input(lines: 0, total: 1710)))
    }

    func testLiveFindingsOnScreenBlockAcceptance() {
        // The bug found by the UI suite: `openDiscrepancyCount` counts *stored* discrepancies,
        // which do not exist until the user has already acted. A fresh mismatch is unaddressed.
        let decision = InvoiceAcceptance.decide(input(unaddressed: 1))
        XCTAssertEqual(try? decision.blockValue(), .openFindings(count: 1))
    }

    func testStoredAndLiveFindingsAreCountedTogether() {
        let decision = InvoiceAcceptance.decide(input(openRecorded: 2, unaddressed: 1))
        XCTAssertEqual(try? decision.blockValue(), .openFindings(count: 3))
    }

    func testTheOpenFindingsExplanationNamesTheCountAndSaysHowToClearIt() {
        let one = InvoiceAcceptanceBlock.openFindings(count: 1).explanation
        XCTAssertTrue(one.contains("One possible mismatch"))
        XCTAssertTrue(one.contains("record a follow-up"))

        let several = InvoiceAcceptanceBlock.openFindings(count: 4).explanation
        XCTAssertTrue(several.contains("4 possible mismatches"))
    }

    func testOpenFindingsAreFixedOnThisScreenSoThereIsNoEditRoute() {
        XCTAssertNil(InvoiceAcceptanceBlock.openFindings(count: 1).editRouteTitle)
    }

    func testAnAlreadyAcceptedInvoiceIsNotAcceptedTwice() {
        // Persisting exactly once is the requirement; refusing the second press is how.
        XCTAssertEqual(
            try? InvoiceAcceptance.decide(input(status: .accepted)).blockValue(),
            .alreadyAccepted
        )
    }

    func testAcceptanceOutranksEmptinessSoTheMessageIsNeverConfusing() {
        // An accepted invoice with nothing on it reports that it is accepted, not that it is
        // empty: the user's next question is "did my tap work", not "what is missing".
        XCTAssertEqual(
            try? InvoiceAcceptance.decide(input(lines: 0, total: 0, status: .accepted)).blockValue(),
            .alreadyAccepted
        )
    }

    func testTheControlTitleTellsTheTruthInBothStates() {
        XCTAssertEqual(InvoiceAcceptance.actionTitle(input()), "Accept this invoice")
        XCTAssertEqual(InvoiceAcceptance.actionTitle(input(status: .accepted)), "Accepted")
    }

    func testEveryBlockExplainsItselfInWordsAUserCanAct() {
        for block in [
            InvoiceAcceptanceBlock.nothingRecorded,
            .openFindings(count: 2),
            .alreadyAccepted,
        ] {
            XCTAssertFalse(block.explanation.isEmpty, "\(block)")
            XCTAssertGreaterThan(block.explanation.count, 30, "\(block)")
        }
    }

    // MARK: - Accepting an invoice on a rental that is already filed away

    /// Archived is past Resolved, and `.resolve` only moves a rental *into* Resolved.
    ///
    /// The invoice screen used to run that transition unconditionally when the user accepted an
    /// invoice. On an archived rental the state machine refused — "Resolve is not available while
    /// this item is Archived" — and the refusal rolled the acceptance back, so the button could
    /// never work. These two facts are why the screen now only resolves when resolving would
    /// actually move the rental forward.
    func testArchivedIsPastResolved() {
        XCTAssertGreaterThan(
            RentalItemStatus.archived.order, RentalItemStatus.resolved.order,
            "a rental is archived after it is resolved, so resolving it again is not a step forward"
        )
    }

    func testResolveIsNotAvailableFromArchived() {
        let intents = StatusTransitionService.availableIntents(for: .archived)
        XCTAssertFalse(
            intents.contains { if case .resolve = $0 { return true } else { return false } },
            "an archived rental cannot be resolved, which is why the invoice screen must not try"
        )
    }

    /// And the acceptance decision itself does not care about the rental's status: an invoice with
    /// a total and nothing outstanding is acceptable whatever the rental has since become.
    func testAnInvoiceStaysAcceptableWhateverTheRentalStatusIs() {
        let input = InvoiceAcceptanceInput(
            openRecordedDiscrepancies: 0,
            unaddressedFindings: 0,
            lineCount: 0,
            invoiceTotal: Decimal(string: "25.00", locale: Locale(identifier: "en_US_POSIX"))!,
            currentStatus: .notReviewed
        )
        XCTAssertTrue(InvoiceAcceptance.canAccept(input))
    }
}

private extension Result where Success == Void, Failure == InvoiceAcceptanceBlock {
    func blockValue() throws -> InvoiceAcceptanceBlock {
        switch self {
        case .success: throw XCTSkip("expected a block")
        case let .failure(block): return block
        }
    }
}
