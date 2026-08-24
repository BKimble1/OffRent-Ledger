import Foundation
import XCTest
@testable import OffRentDomain

/// The guided walkthrough.
///
/// The reason these tests are worth having: the guide's only job is to always know which step
/// somebody is on, and the failure mode is a user stranded on a step they have already done with
/// no way forward. Every status has to map somewhere.
final class GuidedTourTests: XCTestCase {

    func testEveryStatusMapsToAStep() {
        for status in RentalItemStatus.allCases {
            // Nothing to assert about which one — only that asking never traps. A status added
            // later without a step is a person stuck on a screen with a bar that never changes.
            _ = GuidedTourStep.step(for: status)
        }
    }

    func testNoRentalYetMeansTheFirstStep() {
        XCTAssertEqual(GuidedTourStep.step(for: nil), .createRental)
    }

    func testTheStepFollowsTheWorkflowInOrder() {
        let journey: [(RentalItemStatus, GuidedTourStep)] = [
            (.draft, .markDone),
            (.active, .markDone),
            (.contactVendor, .recordConfirmation),
            (.confirmationRecorded, .acknowledgePickup),
            (.awaitingPickup, .recordPickup),
            (.pickedUp, .awaitInvoice),
            (.awaitingInvoice, .attachInvoice),
            (.invoiceReview, .reviewInvoice),
            (.needsFollowUp, .reviewInvoice),
            (.resolved, .finished),
        ]
        for (status, expected) in journey {
            XCTAssertEqual(
                GuidedTourStep.step(for: status), expected,
                "\(status.rawValue) should put the guide on \(expected.rawValue)"
            )
        }
    }

    /// Somebody who archived the rental they were practising on has finished with it. A guide
    /// still pointing at an archived record is a guide nobody can leave.
    func testArchivingTheRentalFinishesTheGuideRatherThanStrandingIt() {
        XCTAssertEqual(GuidedTourStep.step(for: .archived), .finished)
        XCTAssertTrue(GuidedTourStep.step(for: .archived).isFinished)
    }

    func testStepNumbersAreSequentialAndExcludeTheEndState() {
        XCTAssertFalse(GuidedTourStep.walkable.contains(.finished))
        XCTAssertEqual(GuidedTourStep.walkable.map(\.number), Array(1...GuidedTourStep.count))
        XCTAssertEqual(GuidedTourStep.createRental.number, 1)
        XCTAssertEqual(GuidedTourStep.reviewInvoice.number, GuidedTourStep.count)
    }

    func testEveryStepSaysSomethingAndNamesASymbol() {
        for step in GuidedTourStep.allCases {
            XCTAssertFalse(step.title.isEmpty, "\(step.rawValue) has no title")
            XCTAssertFalse(step.instruction.isEmpty, "\(step.rawValue) has no instruction")
            XCTAssertFalse(step.symbol.isEmpty, "\(step.rawValue) has no symbol")
        }
    }

    /// The product's standing copy rules, applied to the one surface that tells people what to
    /// tap. This is exactly where "End rental" would slip in.
    func testNoStepClaimsTheAppContactsAnybodyOrEndsARental() {
        let banned = [
            "guaranteed savings", "verified overcharge", "legal proof", "vendor notified",
            "rental successfully ended", "end rental", "cancel the rental", "we will notify",
        ]
        for step in GuidedTourStep.allCases {
            let text = "\(step.title) \(step.instruction)".lowercased()
            for phrase in banned {
                XCTAssertFalse(
                    text.contains(phrase),
                    "\(step.rawValue) says \"\(phrase)\", which this app must never claim"
                )
            }
        }
    }

    /// The confirmation step is the one that has to be unambiguous about who makes the call.
    func testTheConfirmationStepPutsThePhoneCallOnTheUser() {
        let instruction = GuidedTourStep.recordConfirmation.instruction.lowercased()
        XCTAssertTrue(
            instruction.contains("call the yard") || instruction.contains("you call"),
            "the confirmation step must say the user makes the call"
        )
    }
}
