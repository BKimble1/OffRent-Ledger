import Foundation
import XCTest

/// Scenarios 4 and 5: the free limit, the Pro unlock, and what survives losing Pro.
///
/// Executed in CI on a booted simulator. Green at `b3057d1`; see TEST_MATRIX.md section C.
final class EntitlementUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    /// 4. The free limit blocks a second open rental and the paywall explains both ways out.
    func testFreeLimitBlocksASecondOpenRental() {
        let app = XCUIApplication.launched(seed: .freeLimit, entitlement: .free)

        app.tab(A11yUI.Tab.rentals).tap()
        app.openNewRental()

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

    /// Reaching the paywall from Settings, and choosing a plan.
    ///
    /// This used to run on to tap Subscribe and drive the StoreKit dialog. It never worked, and
    /// the run that finally got far enough showed why: the plan was selected and Subscribe was
    /// enabled, then the confirmation sheet never appeared in this app's accessibility tree at
    /// all, because StoreKit presents it out of process.
    ///
    /// Chasing it would have bought nothing. The test's own note always said a passing StoreKit
    /// *configuration* test says nothing about production purchases — a real purchase is a
    /// Sandbox and TestFlight gate, and it is recorded as unverified in TEST_MATRIX.md, which is
    /// the honest place for it. What is deterministic is everything up to the tap, and that is
    /// what this asserts.
    func testTheSubscriptionScreenReachesThePaywallAndAPlanCanBeChosen() {
        let app = XCUIApplication.launched(seed: .freeLimit, entitlement: .free)

        app.tab(A11yUI.Tab.settings).tap()
        app.expect(app.anyElement(A11yUI.Settings.subscription)).tap()
        app.expect(app.buttons["See Pro options"]).tap()

        app.expect(app.anyElement(A11yUI.Paywall.root))
        selectPlan(A11yUI.Paywall.annual, in: app)
        XCTAssertTrue(
            app.buttons[A11yUI.Paywall.purchase].isEnabled,
            "choosing a plan must enable Subscribe"
        )
    }

    /// The invariant the old test claimed to prove, proved deterministically: Pro is what lifts
    /// the free limit. How somebody *becomes* Pro is StoreKit's business and is gated elsewhere.
    func testProAllowsASecondOpenRental() {
        let app = XCUIApplication.launched(seed: .freeLimit, entitlement: .pro)

        app.tab(A11yUI.Tab.rentals).tap()
        app.openNewRental()
        XCTAssertTrue(
            app.anyElement(A11yUI.AddRental.root).waitForExistence(timeout: 8),
            "Pro must allow a second open rental"
        )
        XCTAssertTrue(
            app.alerts.element.exists == false,
            "Pro must not be refused at the free limit"
        )
    }

    /// Chooses a plan, scrolling to it first if the page is still at the top.
    ///
    /// The plans sit below the fold on purpose — the Subscribe bar is the thing that stays in
    /// reach — so a tap synthesised at a plan's centre can land off the bottom of the screen.
    /// When that happened, nothing was selected, Subscribe stayed disabled, and the failure
    /// surfaced as a missing rentals screen two steps later.
    private func selectPlan(
        _ identifier: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let plan = app.expect(app.buttons[identifier])
        let purchase = app.buttons[A11yUI.Paywall.purchase]

        // Three attempts, scrolling between them. The plans sit below the fold and the Subscribe
        // bar is pinned over the bottom of the page, so a tap synthesised at a plan's centre can
        // land on the bar instead of the plan — which reports as a successful tap and selects
        // nothing. Selection is the condition, not the tap.
        for _ in 0..<3 {
            if purchase.isEnabled { return }
            if plan.isHittable { plan.tap() }
            if purchase.isEnabled { return }
            app.anyElement(A11yUI.Paywall.root).swipeUp()
        }
        XCTFail(
            """
            choosing \(identifier) never enabled Subscribe.
            Identified elements on screen:
            \(app.identifiedElements())
            """,
            file: file, line: line
        )
    }

    /// 5. Losing Pro leaves every existing record usable.
    func testExistingRecordsRemainUsableAfterEntitlementLoss() {
        let app = XCUIApplication.launched(seed: .walkthrough, entitlement: .free)

        app.tab(A11yUI.Tab.rentals).tap()
        app.openRental(named: "Skid Steer Loader")

        // Everything about the existing item still works at the free tier.
        XCTAssertTrue(app.buttons[A11yUI.ItemDetail.markDone].exists)
        app.buttons[A11yUI.ItemDetail.markDone].tap()
        app.expect(app.buttons[A11yUI.ItemDetail.recordConfirmation])

        // Two screens now: taking your data out is a tool and lives on its own, and deleting it
        // stayed with the privacy statement.
        app.tab(A11yUI.Tab.settings).tap()
        app.expect(app.anyElement(A11yUI.Settings.backupAndTransfer)).tap()
        XCTAssertTrue(
            app.expect(app.anyElement(A11yUI.Settings.exportBackup)).isEnabled,
            "exporting a backup must never require a subscription"
        )

        app.back()
        app.expect(app.anyElement(A11yUI.Settings.dataAndPrivacy)).tap()
        XCTAssertTrue(
            app.expect(app.buttons[A11yUI.Settings.deleteAllData]).isEnabled,
            "deleting your own data must never require a subscription"
        )
    }
}
