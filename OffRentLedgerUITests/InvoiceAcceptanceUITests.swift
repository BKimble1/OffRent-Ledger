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
        app.expect(app.staticTexts["Skid Steer Loader"]).tap()
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
        app.tab(A11yUI.Tab.audit).tap()
        app.expect(app.staticTexts["Skid Steer Loader"], timeout: 8)
        app.expect(app.anyElement(A11yUI.Audit.awaitingReview))
        app.expect(app.staticTexts["Cedar Ridge Equipment Rental"], timeout: 8).tap()

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
        app.expect(app.staticTexts["Skid Steer Loader"]).tap()
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

        let reason = app.expect(app.staticTexts[A11yUI.Audit.resolveBlockedReason], timeout: 5)
        XCTAssertTrue(
            reason.label.contains("no total and no lines"),
            "the refusal must be specific, not merely a greyed button: \\(reason.label)"
        )
        XCTAssertTrue(
            app.buttons[A11yUI.Audit.editInvoice].exists,
            "a blocked acceptance must offer the route that unblocks it"
        )

        // And that route actually opens the invoice form, preloaded.
        app.tapWhenHittable(app.buttons[A11yUI.Audit.editInvoice])
        XCTAssertTrue(
            app.textFields["currencyField.Invoice total"].waitForExistence(timeout: 8),
            "Edit invoice must open the invoice form"
        )
    }

    /// The comparison rows never run off the right edge, at any supported text size.
    func testTheComparisonRowsStayInsideTheScreen() {
        let app = XCUIApplication.launched()

        app.tab(A11yUI.Tab.rentals).tap()
        app.expect(app.staticTexts["Skid Steer Loader"]).tap()
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
