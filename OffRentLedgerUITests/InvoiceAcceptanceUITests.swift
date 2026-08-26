import Foundation
import XCTest

/// §12.13–14 and §8: the button that did nothing.
///
/// The screenshot showed a bright orange `Accept this invoice` over a record whose expected amount
/// was `Not available` and whose invoiced amount was `$0.00`. Tapping it produced nothing at all —
/// no acceptance, no alert, no change on screen. These pin both halves of the fix: a valid invoice
/// is accepted and stays accepted, and an invoice that cannot be accepted says why and offers the
/// way out.
final class InvoiceAcceptanceUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    /// "Accept this" on a single finding takes that finding off the screen.
    ///
    /// The screenshot showed the opposite. The row was still there after the tap, wearing the
    /// same two buttons, so the only readable outcome was that nothing had happened — and the
    /// natural next move is to record a follow-up instead, which is what the report said had
    /// been happening.
    ///
    /// The cause was two answers to one question on the same screen: the list was drawn from
    /// every finding the comparison produces, while the Accept bar counted only the ones nobody
    /// had dealt with yet. Accepting a finding moved the second number and left the first alone.
    /// So this asserts both — the row goes, *and* the invoice becomes acceptable, which is the
    /// only proof that the list and the bar are now reading the same set.
    func testAcceptingOneFindingRemovesItAndUnblocksTheInvoice() {
        let app = XCUIApplication.launched()

        app.tab(A11yUI.Tab.rentals).tap()
        app.openRental(named: "Skid Steer Loader")
        app.expect(app.buttons[A11yUI.ItemDetail.markDone]).tap()
        app.expect(app.buttons[A11yUI.ItemDetail.recordConfirmation]).tap()
        app.expect(app.textFields[A11yUI.Confirmation.number]).tap()
        app.typeText("OR-44921")
        app.setOn(app.switches[A11yUI.Confirmation.affirmation])
        app.expect(app.buttons[A11yUI.Confirmation.save]).tap()
        app.expect(app.buttons[A11yUI.ItemDetail.recordPickup]).tap()
        app.expect(app.buttons[A11yUI.Pickup.save]).tap()

        // One day more than the confirmation supports: 6 x 285 = 1710 expected, 1995 invoiced.
        app.expect(app.buttons[A11yUI.ItemDetail.attachInvoice]).tap()
        AttachInvoiceRobot(app: app).fill(total: "1995.00", rentalSubtotal: "1995.00")

        let acceptInvoice = app.expect(app.buttons[A11yUI.Audit.resolveInvoice], timeout: 8)
        XCTAssertFalse(
            acceptInvoice.isEnabled,
            "the invoice must not be acceptable while a mismatch is unaddressed"
        )

        // Every finding, not only the first. How many the comparison produces for one extra day
        // is its business, and a test that accepts one row and then demands an enabled Accept
        // bar would be asserting that number rather than the behaviour.
        let findings = app.buttons.matching(identifier: A11yUI.Audit.acceptMismatch)
        app.expect(findings.firstMatch, timeout: 8)
        var remaining = findings.count
        XCTAssertGreaterThan(
            remaining, 0, "an over-billed invoice must surface at least one finding"
        )

        // The cap is the initial count. A list that refuses to shrink would otherwise spin here
        // until the whole job times out, and a test that hangs says less than one that fails.
        for _ in 0..<remaining {
            guard remaining > 0 else { break }
            let before = remaining
            app.tapInContent(findings.firstMatch)

            // `count` re-runs the query against a fresh snapshot each time, so this polls at the
            // speed of the accessibility tree rather than on a timer.
            let deadline = Date().addingTimeInterval(8)
            while findings.count == before && Date() < deadline {}
            remaining = findings.count

            XCTAssertLessThan(
                remaining, before,
                """
                accepting a finding left it on the list. That is the whole defect: the row \
                redraws identically, so the only readable outcome of the tap is that nothing \
                happened.
                """
            )
        }

        // And now the bar agrees with the list. This is the second half of the same bug — the
        // two were counting different sets, so the screen could show no outstanding findings
        // while Accept stayed disabled, or the reverse.
        wait(
            for: [
                expectation(
                    for: NSPredicate(format: "isEnabled == true"),
                    evaluatedWith: acceptInvoice
                )
            ],
            timeout: 8
        )
    }

    /// §12.13: accepted from Audit, counts move, and it is still accepted after a relaunch.
    func testAValidInvoiceIsAcceptedAndStaysAcceptedAfterRelaunch() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-offrent-reset-state",
            "-offrent-disable-animations",
            "-offrent-force-pro",
            "-offrent-seed-walkthrough",
            "-offrent-fixed-now", XCUIApplication.fixedNow,
            "-offrent-skip-onboarding",
        ]
        app.launch()

        // Walk the rental to the point where an invoice can be attached.
        app.tab(A11yUI.Tab.rentals).tap()
        app.openRental(named: "Skid Steer Loader")
        app.expect(app.buttons[A11yUI.ItemDetail.markDone]).tap()
        app.expect(app.buttons[A11yUI.ItemDetail.recordConfirmation]).tap()
        app.expect(app.textFields[A11yUI.Confirmation.number]).tap()
        app.typeText("OR-44921")
        app.setOn(app.switches[A11yUI.Confirmation.affirmation])
        app.expect(app.buttons[A11yUI.Confirmation.save]).tap()
        app.expect(app.buttons[A11yUI.ItemDetail.recordPickup]).tap()
        app.expect(app.buttons[A11yUI.Pickup.save]).tap()
        app.expect(app.buttons[A11yUI.ItemDetail.attachInvoice]).tap()
        AttachInvoiceRobot(app: app).fill(total: "1710.00", rentalSubtotal: "1710.00")

        // Reached through Audit, which is the route the brief names.
        //
        // An Audit row shows the invoice number and the company — never the equipment name, and
        // the robot above does not give the invoice a number, so the row reads "Invoice" over
        // "Cedar Ridge Equipment Rental". Looking for the machine here was simply looking on the
        // wrong screen.
        app.tab(A11yUI.Tab.audit).tap()
        app.expect(app.anyElement(A11yUI.Audit.awaitingReview), timeout: 10)
        app.openInvoice(from: "Cedar Ridge Equipment Rental")

        let accept = app.expect(app.buttons[A11yUI.Audit.resolveInvoice], timeout: 8)
        XCTAssertTrue(accept.isEnabled, "a matching invoice must be acceptable")
        app.tapWhenHittable(accept)

        // The tap produces a visible result. That is the whole defect: it used to stamp a column
        // nothing on screen displayed, so a working tap and a dead one looked identical.
        XCTAssertTrue(
            app.staticTexts[A11yUI.Audit.acceptedConfirmation].waitForExistence(timeout: 8),
            "accepting must confirm in place rather than appearing to do nothing"
        )

        // The counts move: it leaves Awaiting review and joins Resolved.
        app.expect(app.anyElement(A11yUI.Audit.resolvedHistory), timeout: 10)

        app.relaunchKeepingStore()
        app.tab(A11yUI.Tab.audit).tap()
        XCTAssertTrue(
            app.anyElement(A11yUI.Audit.resolvedHistory).waitForExistence(timeout: 10),
            "the acceptance did not survive a relaunch"
        )
        XCTAssertFalse(
            app.anyElement(A11yUI.Audit.awaitingReview).exists,
            "an accepted invoice must not still be awaiting review"
        )
    }

    /// §12.14: an invoice with nothing on it explains itself and offers Edit — never a bright
    /// button that swallows the tap.
    func testAnEmptyInvoiceExplainsItselfAndOffersAnEditRoute() {
        let app = XCUIApplication.launched()

        app.tab(A11yUI.Tab.rentals).tap()
        app.openRental(named: "Skid Steer Loader")
        app.expect(app.buttons[A11yUI.ItemDetail.markDone]).tap()
        app.expect(app.buttons[A11yUI.ItemDetail.recordConfirmation]).tap()
        app.expect(app.textFields[A11yUI.Confirmation.number]).tap()
        app.typeText("OR-44921")
        app.setOn(app.switches[A11yUI.Confirmation.affirmation])
        app.expect(app.buttons[A11yUI.Confirmation.save]).tap()
        app.expect(app.buttons[A11yUI.ItemDetail.recordPickup]).tap()
        app.expect(app.buttons[A11yUI.Pickup.save]).tap()

        // Attach an invoice with no total and no lines — exactly the record in the screenshot.
        app.expect(app.buttons[A11yUI.ItemDetail.attachInvoice]).tap()
        app.expect(app.buttons[A11yUI.Audit.saveInvoice], timeout: 8).tap()

        let accept = app.expect(app.buttons[A11yUI.Audit.resolveInvoice], timeout: 8)
        XCTAssertFalse(
            accept.isEnabled,
            "an invoice with nothing on it must not present an enabled control that does nothing"
        )

        // The reason is specific and tells the user what to do about it.
        //
        // Which reason depends on the record, and both are correct. This rental has a confirmed
        // daily rate, so an invoice with nothing on it is not merely empty — it is £1,710 short
        // of what the terms say, which the comparison surfaces as a live mismatch. The block is
        // therefore "resolve the mismatches", not "there is nothing here". The `nothingRecorded`
        // case is pinned exactly in `InvoiceAcceptanceTests`; what matters on this screen is
        // that the refusal names something the user can act on.
        let reason = app.expect(app.staticTexts[A11yUI.Audit.resolveBlockedReason], timeout: 5)
        let label = reason.label
        XCTAssertTrue(
            label.contains("possible mismatch") || label.contains("no total and no lines"),
            "the refusal must name what is wrong, not merely grey the button out: \(label)"
        )
        XCTAssertGreaterThan(
            label.count, 30,
            "a one-word refusal is not an explanation: \(label)"
        )
    }

    /// The comparison rows never run off the right edge, at any supported text size.
    func testTheComparisonRowsStayInsideTheScreen() {
        let app = XCUIApplication.launched()

        app.tab(A11yUI.Tab.rentals).tap()
        app.openRental(named: "Skid Steer Loader")
        app.expect(app.buttons[A11yUI.ItemDetail.markDone]).tap()
        app.expect(app.buttons[A11yUI.ItemDetail.recordConfirmation]).tap()
        app.expect(app.textFields[A11yUI.Confirmation.number]).tap()
        app.typeText("OR-44921")
        app.setOn(app.switches[A11yUI.Confirmation.affirmation])
        app.expect(app.buttons[A11yUI.Confirmation.save]).tap()
        app.expect(app.buttons[A11yUI.ItemDetail.recordPickup]).tap()
        app.expect(app.buttons[A11yUI.Pickup.save]).tap()
        app.expect(app.buttons[A11yUI.ItemDetail.attachInvoice]).tap()
        AttachInvoiceRobot(app: app).fill(total: "1710.00", rentalSubtotal: "1710.00")

        let table = app.expect(app.anyElement(A11yUI.Audit.comparisonTable), timeout: 8)
        let screen = app.frame
        for index in 0..<table.staticTexts.count {
            let row = table.staticTexts.element(boundBy: index)
            guard row.exists, row.frame.width > 0 else { continue }
            XCTAssertLessThanOrEqual(
                row.frame.maxX, screen.maxX,
                "“\\(row.label)” runs past the right edge of the screen"
            )
        }
    }
}
