import Foundation
import XCTest

/// Scenario 1 and 2 of the required end-to-end set.
///
/// Executed in CI on a booted simulator. Green at `b3057d1`, then rewritten for the reusable
/// company picker; see TEST_MATRIX.md section C.
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
        app.openNewRental()

        // The company is a reusable record chosen from a picker, not four text fields inlined
        // into this form. Creating one here must come back to the draft with the machine name
        // still in it — which is the §3 requirement, asserted immediately below.
        app.fillMinimalRental(
            equipment: "Mini Excavator", company: "Timberline Machinery", dailyRate: "410.00"
        )
        // Revealed before it is read. Filling the rate scrolled the form down to reach it, and
        // a `Form` row that has scrolled *off* is gone from the accessibility tree exactly as
        // surely as one that has never scrolled *on* — reading `.value` on it throws a snapshot
        // error rather than returning nil, so the failure named the wrong thing entirely.
        XCTAssertEqual(
            app.reveal(app.textFields[A11yUI.AddRental.equipmentName], searching: .above).value as? String,
            "Mini Excavator",
            "creating a company from inside the draft discarded what was already typed"
        )

        app.tapWhenHittable(app.buttons[A11yUI.AddRental.save])

        XCTAssertTrue(
            app.rentalIsListed("Mini Excavator", timeout: 8),
            "saving did not put the rental where the user could see it"
        )

        app.relaunchKeepingStore()
        app.tab(A11yUI.Tab.rentals).tap()
        XCTAssertTrue(
            app.rentalIsListed("Mini Excavator"),
            "the rental did not survive a relaunch"
        )
    }

    /// 2. Done → contact vendor → confirmation → pickup → invoice → resolve, with no mismatch.
    func testFullWorkflowToResolutionWithNoMismatch() {
        let app = XCUIApplication.launched()

        app.tab(A11yUI.Tab.rentals).tap()
        app.openRental(named: "Skid Steer Loader")

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

    /// 3. The evidence packet sheet opens from a rental.
    ///
    /// This screen carried an `.alert` on the same modifier chain as two `.sheet`s. That is the
    /// arrangement the invoice screen already proved breaks presentation: once the alert has
    /// shown and been dismissed, setting a sheet's boolean does nothing. Both sheets on this
    /// screen — the evidence packet and Reopen — were one refusal away from becoming dead taps,
    /// with nothing on screen to say so. They are now one `.sheet(item:)`, which cannot express
    /// the ambiguity, and this is the test that says the mechanism still presents.
    func testTheEvidencePacketSheetOpensFromARental() {
        let app = XCUIApplication.launched()

        app.tab(A11yUI.Tab.rentals).tap()
        app.openRental(named: "Skid Steer Loader")

        // Near the bottom of a long list, so it is revealed before it is tapped.
        app.revealAndTap(app.buttons[A11yUI.ItemDetail.exportEvidence])

        XCTAssertTrue(
            app.expect(app.anyElement(A11yUI.EvidenceExport.root)).exists,
            "tapping Export evidence packet must present the packet sheet"
        )

        // And it closes again, leaving the rental where it was.
        app.expect(app.buttons["Done"]).tap()
        XCTAssertTrue(app.expect(app.buttons[A11yUI.ItemDetail.exportEvidence]).exists)
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

    /// The scanner is on the home screen.
    ///
    /// It used to sit four taps in — Rentals, +, New rental, Scan the rental contract — which is
    /// a long way from the thing the app is fastest at. The card is asserted on Today with a
    /// rental present *and* on an empty install, because the user with nothing on rent is the one
    /// who most needs it.
    func testTheScannerIsOnTheHomeScreen() {
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.expect(app.anyElement(A11yUI.Today.scanCard)).exists)
        XCTAssertTrue(app.expect(app.buttons[A11yUI.Today.scanStart]).isEnabled)
    }

    func testTheScannerIsThereWithNothingOnRentEither() {
        let app = XCUIApplication.launched(seed: .empty)
        XCTAssertTrue(app.expect(app.anyElement(A11yUI.Today.emptyState)).exists)
        XCTAssertTrue(
            app.reveal(app.anyElement(A11yUI.Today.scanCard)).exists,
            "an empty Today is exactly where the quickest way to add a contract belongs"
        )
    }

    /// iOS is never asked without the reason being shown first.
    ///
    /// The permission alert can be answered once. "Turn on reminders" opens an explanation with a
    /// Continue button, and only Continue reaches `requestAuthorization` — so a user who reads it
    /// and backs out has spent nothing, and App Review sees the purpose before the prompt.
    func testTurningOnRemindersExplainsItselfBeforeAskingIOS() {
        let app = XCUIApplication.launched()

        app.tab(A11yUI.Tab.settings).tap()
        app.revealAndTap(app.anyElement(A11yUI.Settings.reminders))
        app.revealAndTap(app.buttons[A11yUI.Settings.remindersEnable])

        XCTAssertTrue(
            app.expect(app.anyElement(A11yUI.Settings.remindersPriming)).exists,
            "the explanation must come before the system prompt, not after it"
        )
        XCTAssertTrue(app.expect(app.buttons[A11yUI.Settings.remindersPrimingContinue]).isEnabled)

        // Backing out costs nothing: iOS was never asked, and the button is still there.
        app.expect(app.buttons[A11yUI.Settings.remindersPrimingNotNow]).tap()
        XCTAssertTrue(app.expect(app.buttons[A11yUI.Settings.remindersEnable]).exists)
    }
}
