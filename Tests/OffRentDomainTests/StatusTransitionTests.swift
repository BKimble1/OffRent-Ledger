import XCTest
@testable import OffRentDomain

/// The state machine. Its most important property is a *negative* one: there is no sequence of
/// intents that reaches "the vendor confirmed" without the user saying they contacted the vendor.
final class StatusTransitionTests: XCTestCase {

    private let now = date(2026, 5, 11, 9)

    private func validEvidence() -> ConfirmationEvidence {
        ConfirmationEvidence(
            confirmationNumber: "OR-44921",
            contactMethod: .phone,
            confirmedAt: now,
            userAffirmedContact: true
        )
    }

    // MARK: - The safety property

    func testConfirmationIsRefusedWithoutTheUserAffirmingContact() {
        var evidence = validEvidence()
        evidence.userAffirmedContact = false
        let result = StatusTransitionService.apply(
            .recordVendorConfirmation(evidence), to: .contactVendor
        )
        guard case let .failure(rejection) = result else {
            return XCTFail("must refuse: the app cannot know a call happened")
        }
        XCTAssertEqual(rejection, .confirmationInvalid(.contactNotAffirmed))
    }

    func testNoIntentSkipsContactVendorOnTheWayToConfirmation() {
        // Exhaustive: from every status, no intent may land on `.confirmationRecorded` unless the
        // item was already in `.contactVendor`. This is the property that stops a refactor from
        // quietly creating a "confirm" shortcut somewhere else in the app.
        for status in RentalItemStatus.allCases where status != .contactVendor {
            for intent in allIntents(evidence: validEvidence()) {
                guard case let .success(outcome) = StatusTransitionService.apply(intent, to: status)
                else { continue }
                XCTAssertNotEqual(
                    outcome.resultingStatus, .confirmationRecorded,
                    "\(intent.label) reached Confirmation Recorded from \(status.displayName)"
                )
            }
        }
    }

    func testConfirmationRequiresANumberOrAnExplicitAcknowledgementThatThereIsNone() {
        var evidence = validEvidence()
        evidence.confirmationNumber = "   "
        let refused = StatusTransitionService.apply(
            .recordVendorConfirmation(evidence), to: .contactVendor
        )
        guard case let .failure(rejection) = refused else { return XCTFail("blank number must be refused") }
        XCTAssertEqual(rejection, .confirmationInvalid(.missingConfirmationNumber))

        evidence.acknowledgedNoConfirmationNumber = true
        guard case .success = StatusTransitionService.apply(
            .recordVendorConfirmation(evidence), to: .contactVendor
        ) else {
            return XCTFail("an explicit acknowledgement is a valid answer")
        }
    }

    func testRecordingConfirmationWritesTheConfirmationEvent() {
        guard case let .success(outcome) = StatusTransitionService.apply(
            .recordVendorConfirmation(validEvidence()), to: .contactVendor
        ) else { return XCTFail("valid evidence must be accepted") }
        XCTAssertEqual(outcome.events, [.vendorConfirmationRecorded])
    }

    // MARK: - The whole table

    func testEveryDeclaredTransitionIsReachableByAnIntent() {
        // Guards against a table entry that no intent can actually use — a dead edge that reads
        // as supported behaviour in the generated documentation.
        for (from, destinations) in StatusTransitionService.allowedTransitions {
            for destination in destinations {
                let reached = allIntents(evidence: validEvidence()).contains { intent in
                    if case let .success(outcome) = StatusTransitionService.apply(intent, to: from) {
                        return outcome.resultingStatus == destination
                    }
                    return false
                }
                XCTAssertTrue(
                    reached, "no intent moves \(from.displayName) → \(destination.displayName)"
                )
            }
        }
    }

    func testEveryIntentOutcomeIsInTheDeclaredTableExceptReopen() {
        for status in RentalItemStatus.allCases {
            for intent in allIntents(evidence: validEvidence()) {
                if case .reopen = intent { continue }
                guard case let .success(outcome) = StatusTransitionService.apply(intent, to: status)
                else { continue }
                XCTAssertTrue(
                    StatusTransitionService.canTransition(from: status, to: outcome.resultingStatus),
                    "\(intent.label) produced an undeclared edge \(status) → \(outcome.resultingStatus)"
                )
            }
        }
    }

    func testForwardHappyPath() {
        var status = RentalItemStatus.draft
        let steps: [(TransitionIntent, RentalItemStatus)] = [
            (.activate, .active),
            (.markEquipmentDone, .contactVendor),
            (.recordVendorConfirmation(validEvidence()), .confirmationRecorded),
            (.acknowledgeAwaitingPickup, .awaitingPickup),
            (.recordPickup(PickupEvidence(pickedUpAt: now)), .pickedUp),
            (.beginAwaitingInvoice, .awaitingInvoice),
            (.attachInvoice, .invoiceReview),
            (.resolve(openDiscrepancyCount: 0), .resolved),
            (.archive, .archived),
        ]
        for (intent, expected) in steps {
            guard case let .success(outcome) = StatusTransitionService.apply(intent, to: status) else {
                return XCTFail("\(intent.label) refused from \(status.displayName)")
            }
            XCTAssertEqual(outcome.resultingStatus, expected)
            status = outcome.resultingStatus
        }
    }

    func testSkippingAStepIsRejected() {
        let result = StatusTransitionService.apply(
            .recordPickup(PickupEvidence(pickedUpAt: now)), to: .active
        )
        guard case let .failure(rejection) = result else { return XCTFail("must be rejected") }
        XCTAssertEqual(rejection, .notAllowed(from: .active, intent: "Record pickup"))
    }

    func testArchivedIsTerminalExceptForReopen() {
        XCTAssertEqual(StatusTransitionService.allowedTransitions[.archived], [])
        for intent in allIntents(evidence: validEvidence()) {
            if case .reopen = intent { continue }
            guard case .success = StatusTransitionService.apply(intent, to: .archived) else { continue }
            XCTFail("\(intent.label) escaped Archived without an explicit reopen")
        }
    }

    // MARK: - Resolving

    func testResolvingIsRefusedWhileMismatchesAreOpen() {
        let result = StatusTransitionService.apply(
            .resolve(openDiscrepancyCount: 3), to: .invoiceReview
        )
        guard case let .failure(rejection) = result else { return XCTFail("must be refused") }
        XCTAssertEqual(rejection, .cannotResolveWithOpenDiscrepancies(count: 3))
        XCTAssertTrue(rejection.message.contains("3 possible mismatches"))
    }

    func testSingularMessageForOneOpenMismatch() {
        let rejection = TransitionRejection.cannotResolveWithOpenDiscrepancies(count: 1)
        XCTAssertTrue(rejection.message.hasPrefix("One possible mismatch"))
    }

    func testFollowUpRequiresAReason() {
        guard case let .failure(rejection) = StatusTransitionService.apply(
            .flagFollowUp(reason: "  \n "), to: .invoiceReview
        ) else { return XCTFail("must be refused") }
        XCTAssertEqual(rejection, .followUpRequiresReason)
    }

    // MARK: - Reopening

    func testReopenRequiresAReason() {
        guard case let .failure(rejection) = StatusTransitionService.apply(
            .reopen(to: .invoiceReview, reason: ""), to: .resolved
        ) else { return XCTFail("must be refused") }
        XCTAssertEqual(rejection, .reopenRequiresReason)
    }

    func testReopenMustMoveBackwards() {
        guard case let .failure(rejection) = StatusTransitionService.apply(
            .reopen(to: .needsFollowUp, reason: "typo"), to: .active
        ) else { return XCTFail("must be refused") }
        XCTAssertEqual(rejection, .reopenMustMoveBackwards(from: .active, to: .needsFollowUp))
    }

    func testCannotReopenIntoDraft() {
        guard case let .failure(rejection) = StatusTransitionService.apply(
            .reopen(to: .draft, reason: "started by mistake"), to: .resolved
        ) else { return XCTFail("must be refused") }
        XCTAssertEqual(rejection, .reopenTargetNotReachable(.draft))
    }

    func testReopenFromArchivedWritesAReopenedEvent() {
        guard case let .success(outcome) = StatusTransitionService.apply(
            .reopen(to: .invoiceReview, reason: "Vendor sent a corrected invoice"), to: .archived
        ) else { return XCTFail("reopen must be allowed with a reason") }
        XCTAssertEqual(outcome.resultingStatus, .invoiceReview)
        XCTAssertEqual(outcome.events, [.reopened])
    }

    // MARK: - Derived properties

    func testOnlyResolvedAndArchivedAreClosed() {
        let closed = RentalItemStatus.allCases.filter { !$0.isOpen }
        XCTAssertEqual(Set(closed), [.resolved, .archived])
    }

    func testOnlyActiveAndContactVendorAccrueRent() {
        // A machine awaiting pickup is off-rent. If this ever changes, the estimate on Today
        // starts climbing after the user has already stopped the clock.
        let accruing = RentalItemStatus.allCases.filter(\.accruesRent)
        XCTAssertEqual(Set(accruing), [.active, .contactVendor])
    }

    func testEveryStatusHasDistinctUserFacingText() {
        let names = Set(RentalItemStatus.allCases.map(\.displayName))
        let symbols = Set(RentalItemStatus.allCases.map(\.symbolName))
        let explanations = Set(RentalItemStatus.allCases.map(\.explanation))
        XCTAssertEqual(names.count, RentalItemStatus.allCases.count)
        XCTAssertEqual(symbols.count, RentalItemStatus.allCases.count)
        XCTAssertEqual(explanations.count, RentalItemStatus.allCases.count)
    }

    func testNoStatusOrEventLabelClaimsTheAppActed() {
        // Belt and braces alongside verify_repository.py: the vocabulary itself must not imply
        // the app ended a rental or contacted anyone.
        let banned = ["rental ended", "successfully ended", "vendor notified", "we notified", "we contacted"]
        let text = (RentalItemStatus.allCases.map { $0.displayName + " " + $0.explanation }
            + RentalEventType.allCases.map(\.displayName))
            .joined(separator: " ")
            .lowercased()
        for phrase in banned {
            XCTAssertFalse(text.contains(phrase), "banned phrase in workflow vocabulary: \(phrase)")
        }
    }

    private func allIntents(evidence: ConfirmationEvidence) -> [TransitionIntent] {
        [
            .activate,
            .markEquipmentDone,
            .recordVendorConfirmation(evidence),
            .acknowledgeAwaitingPickup,
            .recordPickup(PickupEvidence(pickedUpAt: now)),
            .beginAwaitingInvoice,
            .attachInvoice,
            .flagFollowUp(reason: "reason"),
            .resolve(openDiscrepancyCount: 0),
            .archive,
            .reopen(to: .invoiceReview, reason: "reason"),
        ]
    }
}
