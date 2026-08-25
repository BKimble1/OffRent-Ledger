import Foundation
import XCTest

/// Scenario 3: an invoice with an extra day leaves an open follow-up that survives a relaunch.
///
/// Executed in CI on a booted simulator. Green at `b3057d1`; see TEST_MATRIX.md section C.
final class MismatchUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    func testInvoiceWithAnExtraDayLeavesAnOpenFollowUp() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-offrent-reset-state",
            "-offrent-disable-animations",
            "-offrent-force-pro",
            "-offrent-seed-walkthrough",
            "-offrent-fixed-now", XCUIApplication.fixedNow,
            // Without this the welcome sits in front of the whole scenario. It has been passing
            // only because an earlier test class runs first and persists the flag into the
            // simulator's defaults — run this class on its own and it fails on the first tap.
            "-offrent-skip-onboarding",
        ]
        app.launch()

        app.tab(A11yUI.Tab.rentals).tap()
        app.openRental(named: "Skid Steer Loader")

        app.expect(app.buttons[A11yUI.ItemDetail.markDone]).tap()
        app.expect(app.buttons[A11yUI.ItemDetail.recordConfirmation]).tap()
        app.textFields[A11yUI.Confirmation.number].tap()
        app.typeText("OR-44921")
        app.setOn(app.switches[A11yUI.Confirmation.affirmation])

        // Asserted rather than assumed. When this silently failed, the test reported a missing
        // "record pickup" button three steps later and said nothing about why.
        let save = app.buttons[A11yUI.Confirmation.save]
        XCTAssertTrue(save.isEnabled, "a number and the affirmation must be enough to save")
        save.tap()

        app.expect(app.buttons[A11yUI.ItemDetail.recordPickup]).tap()
        app.buttons[A11yUI.Pickup.save].tap()

        // One more day than the confirmed expectation: 6 × 285 = 1710 expected, 1995 invoiced.
        app.expect(app.buttons[A11yUI.ItemDetail.attachInvoice]).tap()
        AttachInvoiceRobot(app: app).fill(total: "1995.00", rentalSubtotal: "1995.00")

        // Asserted on the figure's own label rather than by searching for a static text called
        // "$285.00". The amount carries an explicit identifier, so the string subscript matches
        // that identifier and never its text — and reading the label is the stronger check
        // anyway: it fails on a wrong number, not only on a missing one.
        let variance = app.expect(app.staticTexts[A11yUI.Audit.possibleVariance])
        XCTAssertEqual(
            variance.label, "$285.00",
            "one extra day at $285 must be surfaced as the possible variance"
        )

        // Accepting must be refused while the mismatch is open — and refused *before* the tap,
        // not after it.
        //
        // This used to assert that tapping Accept raised an alert. That was the old contract, and
        // the screenshots showed why it was the wrong one: the control looked live, and on the
        // one record where the refusal path did not fire it was a button that swallowed the tap
        // in silence. §8 of the brief is explicit — either allow it, or disable it with a
        // specific explanation. So the assertion moved to the stronger place: the state the user
        // can see without touching anything.
        let accept = app.expect(app.buttons[A11yUI.Audit.resolveInvoice])
        XCTAssertFalse(
            accept.isEnabled,
            "Accept must be disabled while a possible mismatch is open, not enabled and inert"
        )
        let reason = app.expect(app.staticTexts[A11yUI.Audit.resolveBlockedReason])
        XCTAssertTrue(
            reason.label.contains("possible mismatch"),
            "the disabled control must name what is blocking it: \(reason.label)"
        )

        // This one is in scrollable content and drifts under the pinned Accept bar and the
        // tab bar, so it has to be scrolled clear rather than merely found.
        app.tapInContent(app.buttons[A11yUI.Audit.recordFollowUp])
        app.expect(app.anyElement(A11yUI.Audit.followUpReason)).tap()
        app.typeText("Billed one day past the OR-44921 confirmation.")
        app.tapWhenHittable(app.buttons["Save"])

        // 15. It is still open after a relaunch.
        app.relaunchKeepingStore()
        app.tab(A11yUI.Tab.audit).tap()
        XCTAssertTrue(
            app.anyElement(A11yUI.Audit.possibleMismatches).waitForExistence(timeout: 10),
            "the unresolved difference must survive a relaunch"
        )
    }

    /// Scenario 6: the scan review sheet never saves without an explicit tap.
    ///
    /// Requires a document camera. `VNDocumentCameraViewController.isSupported` is false on a
    /// simulator, so the app correctly does not draw the scan button and there is nothing to tap.
    /// This is skipped there rather than asserted against a device capability — and the invariant
    /// it guards is separately covered by `ScanReviewCommitTests`, which run the whole pipeline
    /// and assert that discarding it writes nothing.
    func testScanReviewNeverSavesWithoutConfirmation() throws {
        let app = XCUIApplication.launched(seed: .empty)

        app.tab(A11yUI.Tab.rentals).tap()
        app.openNewRental()

        let scan = app.buttons[A11yUI.AddRental.scanButton]
        try XCTSkipUnless(
            scan.waitForExistence(timeout: 5),
            "no document camera on this device, so there is no scan button to open"
        )
        scan.tap()

        // The stub recogniser returns fixture text, so the review sheet appears with suggestions.
        app.expect(app.anyElement(A11yUI.Scan.reviewRoot))
        XCTAssertTrue(app.staticTexts[A11yUI.Scan.explanation].exists)

        // Cancel out of the review. Nothing may have been written.
        app.buttons[A11yUI.Scan.cancelButton].tap()
        app.buttons[A11yUI.AddRental.cancel].tap()

        app.tab(A11yUI.Tab.rentals).tap()
        // Matched the way a row actually reads. `staticTexts[...]` for a machine name can never
        // be true on this list — a row is one combined element — so the old assertion passed
        // whether the scan had written a rental or not, which is no assertion at all.
        XCTAssertFalse(
            app.rentalIsListed("Skid Steer Loader 75HP Closed Cab", timeout: 3),
            "cancelling a scan review must write nothing"
        )
    }
}
