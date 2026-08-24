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

        app.expect(app.anyElement(A11yUI.Paywall.root))
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
        selectPlan(A11yUI.Paywall.annual, in: app)
        XCTAssertTrue(app.buttons[A11yUI.Paywall.purchase].isEnabled)
    }

    /// The StoreKit configuration in the scheme drives this. Passing it says nothing about
    /// production purchases; Sandbox and TestFlight are separate real-device gates.
    func testPurchasingUnlocksUnlimitedOpenRentals() {
        let app = XCUIApplication.launched(seed: .freeLimit, entitlement: .free)

        app.tab(A11yUI.Tab.settings).tap()
        app.expect(app.anyElement(A11yUI.Settings.subscription)).tap()
        app.expect(app.buttons["See Pro options"]).tap()

        app.expect(app.anyElement(A11yUI.Paywall.root))
        selectPlan(A11yUI.Paywall.annual, in: app)

        let purchase = app.buttons[A11yUI.Paywall.purchase]
        XCTAssertTrue(purchase.isEnabled, "choosing a plan must enable Subscribe")
        purchase.tap()

        // Not `app.buttons["Subscribe"]`. The paywall's own primary action carries that label
        // too and matched first, so the last run tapped our own disabled button and then waited
        // ten seconds for a purchase nothing had started.
        let dialogSubscribe = app.buttons.matching(
            NSPredicate(
                format: "label == %@ AND identifier != %@", "Subscribe", A11yUI.Paywall.purchase
            )
        ).firstMatch
        if dialogSubscribe.waitForExistence(timeout: 10) { dialogSubscribe.tap() }
        let confirm = app.buttons["OK"]
        if confirm.waitForExistence(timeout: 10) { confirm.tap() }

        app.tab(A11yUI.Tab.rentals).tap()
        app.expect(app.buttons[A11yUI.Rentals.addRental]).tap()
        XCTAssertTrue(
            app.anyElement(A11yUI.AddRental.root).waitForExistence(timeout: 8),
            "Pro must allow a second open rental"
        )
    }

    /// Chooses a plan, scrolling to it first if the page is still at the top.
    ///
    /// The plans sit below the fold on purpose — the Subscribe bar is the thing that stays in
    /// reach — so a tap synthesised at a plan's centre can land off the bottom of the screen.
    /// When that happened, nothing was selected, Subscribe stayed disabled, and the failure
    /// surfaced as a missing rentals screen two steps later.
    private func selectPlan(_ identifier: String, in app: XCUIApplication) {
        let plan = app.expect(app.buttons[identifier])
        if !plan.isHittable { app.anyElement(A11yUI.Paywall.root).swipeUp() }
        plan.tap()
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
        app.expect(app.anyElement(A11yUI.Settings.dataAndPrivacy)).tap()
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
