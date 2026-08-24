import Foundation
import XCTest

/// Scenario 3: an invoice with an extra day leaves an open follow-up that survives a relaunch.
///
/// NOT EXECUTED — no simulator in the build environment. See TEST_MATRIX.md.
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
        ]
        app.launch()

        app.tab(A11yUI.Tab.rentals).tap()
        app.expect(app.staticTexts["Skid Steer Loader"]).tap()

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

        app.expect(app.staticTexts[A11yUI.Audit.possibleVariance])
        XCTAssertTrue(
            app.staticTexts["$285.00"].exists,
            "one extra day at $285 must be surfaced as the possible variance"
        )

        // Resolve must be refused while the mismatch is open.
        app.buttons[A11yUI.Audit.resolveInvoice].tap()
        XCTAssertTrue(app.alerts.element.waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()

        app.buttons[A11yUI.Audit.recordFollowUp].tap()
        app.expect(app.textViews[A11yUI.Audit.followUpReason]).tap()
        app.typeText("Billed one day past the OR-44921 confirmation.")
        app.buttons["Save"].tap()

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
        app.expect(app.buttons[A11yUI.Rentals.addRental]).tap()

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
        XCTAssertFalse(
            app.staticTexts["Skid Steer Loader 75HP Closed Cab"].exists,
            "cancelling a scan review must write nothing"
        )
    }
}
