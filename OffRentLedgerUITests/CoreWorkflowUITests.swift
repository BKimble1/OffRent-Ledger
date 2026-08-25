import Foundation
import XCTest

/// Scenario 1 and 2 of the required end-to-end set.
///
/// NOT EXECUTED — no simulator in the build environment. See TEST_MATRIX.md.
final class CoreWorkflowUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// 1. Create a rental by hand and confirm it survives a relaunch.
    ///
    /// Uses the on-disk store deliberately: an in-memory store cannot demonstrate persistence,
    /// and a persistence test that cannot fail is not a test.
    func testManuallyCreatedRentalSurvivesRelaunch() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-offrent-reset-state",
            "-offrent-disable-animations",
            "-offrent-force-pro",
            "-offrent-fixed-now", XCUIApplication.fixedNow,
            // See the note in MismatchUITests: a hand-built launch has to ask for this too, or
            // the scenario depends on which class ran before it.
            "-offrent-skip-onboarding",
        ]
        app.launch()

        app.tab(A11yUI.Tab.rentals).tap()
        app.expect(app.buttons[A11yUI.Rentals.addRental]).tap()

        app.expect(app.textFields[A11yUI.AddRental.equipmentName]).tap()
        app.typeText("Mini Excavator")

        app.textFields[A11yUI.AddRental.newVendorName].tap()
        app.typeText("Timberline Machinery")

        app.textFields[A11yUI.AddRental.dailyRate].tap()
        app.typeText("410.00")

        app.buttons[A11yUI.AddRental.save].tap()

        XCTAssertTrue(app.staticTexts["Mini Excavator"].waitForExistence(timeout: 8))

        app.relaunchKeepingStore()
        app.tab(A11yUI.Tab.rentals).tap()
        XCTAssertTrue(
            app.staticTexts["Mini Excavator"].waitForExistence(timeout: 10),
            "the rental did not survive a relaunch"
        )
    }

    /// 2. Done → contact vendor → confirmation → pickup → invoice → resolve, with no mismatch.
    func testFullWorkflowToResolutionWithNoMismatch() {
        let app = XCUIApplication.launched()

        app.tab(A11yUI.Tab.rentals).tap()
        app.expect(app.staticTexts["Skid Steer Loader"]).tap()

        // Mark done. The app must route through Contact Vendor with the disclosure visible.
        app.expect(app.buttons[A11yUI.ItemDetail.markDone]).tap()
        XCTAssertTrue(
            app.expect(app.staticTexts[A11yUI.ItemDetail.disclosure]).exists,
            "the Contact Vendor step must show the disclosure"
        )

        // Record the confirmation.
        app.expect(app.buttons[A11yUI.ItemDetail.recordConfirmation]).tap()
        app.expect(app.staticTexts[A11yUI.Confirmation.disclosure])

        let save = app.buttons[A11yUI.Confirmation.save]
        XCTAssertFalse(save.isEnabled, "Save must be disabled before the affirmation is ticked")

        app.textFields[A11yUI.Confirmation.number].tap()
        app.typeText("OR-44921")
        XCTAssertFalse(save.isEnabled, "a number alone is not enough; the affirmation is required")

        app.setOn(app.switches[A11yUI.Confirmation.affirmation])
        XCTAssertTrue(save.isEnabled)
        save.tap()

        // Pickup.
        app.expect(app.buttons[A11yUI.ItemDetail.recordPickup]).tap()
        app.expect(app.buttons[A11yUI.Pickup.save]).tap()

        // Invoice matching the confirmed expectation.
        app.expect(app.buttons[A11yUI.ItemDetail.attachInvoice]).tap()
        AttachInvoiceRobot(app: app).fill(total: "1710.00", rentalSubtotal: "1710.00")

        let variance = app.expect(app.staticTexts[A11yUI.Audit.possibleVariance])
        XCTAssertEqual(
            variance.label, "$0.00",
            "a matching invoice must show zero possible variance"
        )
        app.buttons[A11yUI.Audit.resolveInvoice].tap()
    }
}

/// Keeps the tapping out of the assertions.
struct AttachInvoiceRobot {
    let app: XCUIApplication

    func fill(total: String, rentalSubtotal: String) {
        app.textFields["currencyField.Invoice total"].tap()
        app.typeText(total)

        // "Add a line" is below the total field and the decimal pad covers it. Tapping it with
        // the keyboard up reports success and adds nothing, and the next step then looks for an
        // Amount field that was never created. Dismissing first is also what a person does, and
        // it exercises the Done button the decimal pad would otherwise have no way out of.
        app.dismissKeyboard()
        app.buttons["Add a line"].tap()

        // A new line is "Other" until somebody says otherwise, and an uncategorised amount
        // deliberately does not count as rent — which is why the last run compared 1,710 expected
        // against 0 invoiced and reported the whole subtotal as the variance. The app is right to
        // refuse to guess; the test has to say what kind of line this is, which is also the thing
        // it is asserting about.
        app.expect(app.anyElement(A11yUI.Audit.lineCategory)).tap()
        app.expect(app.buttons["Rental subtotal"]).tap()

        app.expect(app.textFields["currencyField.Amount"]).tap()
        app.typeText(rentalSubtotal)
        app.dismissKeyboard()

        // Addressed by identifier rather than by the label "Save". The sheet's primary action
        // moved to a bottom bar and reads "Save invoice"; matching on a bare label would also
        // have matched any other Save that happened to be on screen.
        app.expect(app.buttons[A11yUI.Audit.saveInvoice]).tap()
    }
}
