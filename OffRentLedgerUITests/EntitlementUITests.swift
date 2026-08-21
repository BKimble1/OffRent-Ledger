import Foundation
import XCTest

/// Scenarios 4 and 5: the free limit, the Pro unlock, and what survives losing Pro.
///
/// NOT EXECUTED — no simulator in the build environment. See TEST_MATRIX.md.
final class EntitlementUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    /// 4. The free limit blocks a second open rental and the paywall explains both ways out.
    func testFreeLimitBlocksASecondOpenRental() {
        let app = XCUIApplication.launched(seed: .freeLimit, entitlement: .free)

        app.tab(A11yUI.Tab.rentals).tap()
        app.expect(app.buttons[A11yUI.Rentals.addRental]).tap()

        let alert = app.alerts.element
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "a second open rental must be refused")
        XCTAssertTrue(
            alert.staticTexts.element(boundBy: 1).label.contains("Resolve or archive"),
            "the message must name the free way out, not only the paid one"
        )
        alert.buttons["See Pro"].tap()

        app.expect(app.otherElements[A11yUI.Paywall.root])
        XCTAssertTrue(app.buttons[A11yUI.Paywall.monthly].exists)
        XCTAssertTrue(app.buttons[A11yUI.Paywall.annual].exists)
        XCTAssertTrue(app.buttons[A11yUI.Paywall.restore].exists)
        XCTAssertTrue(app.buttons[A11yUI.Paywall.privacy].exists)
        XCTAssertTrue(app.buttons[A11yUI.Paywall.terms].exists)

        // Nothing is preselected, so Subscribe stays disabled until the user chooses.
        XCTAssertFalse(
            app.buttons[A11yUI.Paywall.purchase].isEnabled,
            "no plan may be preselected"
        )
        app.buttons[A11yUI.Paywall.annual].tap()
        XCTAssertTrue(app.buttons[A11yUI.Paywall.purchase].isEnabled)
    }

    /// The StoreKit configuration in the scheme drives this. Passing it says nothing about
    /// production purchases; Sandbox and TestFlight are separate real-device gates.
    func testPurchasingUnlocksUnlimitedOpenRentals() {
        let app = XCUIApplication.launched(seed: .freeLimit, entitlement: .free)

        app.tab(A11yUI.Tab.settings).tap()
        app.expect(app.cells[A11yUI.Settings.subscription]).tap()
        app.expect(app.buttons["See Pro options"]).tap()

        app.expect(app.otherElements[A11yUI.Paywall.root])
        app.buttons[A11yUI.Paywall.annual].tap()
        app.buttons[A11yUI.Paywall.purchase].tap()

        // The StoreKit test dialog is a system sheet.
        let subscribe = app.buttons["Subscribe"]
        if subscribe.waitForExistence(timeout: 10) { subscribe.tap() }
        let confirm = app.buttons["OK"]
        if confirm.waitForExistence(timeout: 10) { confirm.tap() }

        app.tab(A11yUI.Tab.rentals).tap()
        app.expect(app.buttons[A11yUI.Rentals.addRental]).tap()
        XCTAssertTrue(
            app.otherElements[A11yUI.AddRental.root].waitForExistence(timeout: 8),
            "Pro must allow a second open rental"
        )
    }

    /// 5. Losing Pro leaves every existing record usable.
    func testExistingRecordsRemainUsableAfterEntitlementLoss() {
        let app = XCUIApplication.launched(seed: .walkthrough, entitlement: .free)

        app.tab(A11yUI.Tab.rentals).tap()
        app.expect(app.staticTexts["Skid Steer Loader"]).tap()

        // Everything about the existing item still works at the free tier.
        XCTAssertTrue(app.buttons[A11yUI.ItemDetail.markDone].exists)
        app.buttons[A11yUI.ItemDetail.markDone].tap()
        app.expect(app.buttons[A11yUI.ItemDetail.recordConfirmation])

        app.tab(A11yUI.Tab.settings).tap()
        app.expect(app.cells[A11yUI.Settings.dataAndPrivacy]).tap()
        XCTAssertTrue(
            app.expect(app.buttons[A11yUI.Settings.exportBackup]).isEnabled,
            "exporting a backup must never require a subscription"
        )
        XCTAssertTrue(
            app.buttons[A11yUI.Settings.deleteAllData].isEnabled,
            "deleting your own data must never require a subscription"
        )
    }
}
