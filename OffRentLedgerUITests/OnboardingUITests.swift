import Foundation
import XCTest

/// The first run.
///
/// Onboarding is the one screen that, when it goes wrong, goes wrong for everybody at once and is
/// invisible to whoever built it — they installed the app long ago and will never see it again
/// without wiping the device. So the things that would be embarrassing are pinned here.
final class OnboardingUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    func testFirstRunShowsTheWelcomeAndSkippingReachesTheApp() {
        let app = XCUIApplication.launchedAsNewUser()

        app.expect(app.otherElements[A11yUI.Onboarding.welcomeRoot])
        app.expect(app.buttons[A11yUI.Onboarding.welcomeSkip]).tap()

        XCTAssertTrue(
            app.tab(A11yUI.Tab.today).waitForExistence(timeout: 5),
            "skipping the welcome must land in the app, not on another wall"
        )
    }

    func testTheTourCanBeSkippedFromItsFirstPage() {
        let app = XCUIApplication.launchedAsNewUser()

        app.expect(app.buttons[A11yUI.Onboarding.welcomeTour]).tap()
        app.expect(app.otherElements[A11yUI.Onboarding.tourRoot])

        // Skip is on every page, including the first. A tour you have to walk through to leave
        // is not optional, whatever the button says.
        app.expect(app.buttons[A11yUI.Onboarding.tourSkip]).tap()
        XCTAssertTrue(app.tab(A11yUI.Tab.today).waitForExistence(timeout: 5))
    }

    func testTheTourCanBeWalkedToTheEnd() {
        let app = XCUIApplication.launchedAsNewUser()

        app.expect(app.buttons[A11yUI.Onboarding.welcomeTour]).tap()
        app.expect(app.otherElements[A11yUI.Onboarding.tourRoot])

        // Four taps of Next, then the finishing button. If a page is ever added without the
        // footer following, this fails rather than silently stranding somebody mid-tour.
        for step in 1...4 {
            app.expect(app.buttons[A11yUI.Onboarding.tourNext], timeout: 5).tap()
            XCTAssertTrue(
                app.otherElements[A11yUI.Onboarding.tourRoot].exists,
                "the tour closed itself on step \(step)"
            )
        }
        app.expect(app.buttons[A11yUI.Onboarding.tourDone]).tap()
        XCTAssertTrue(app.tab(A11yUI.Tab.today).waitForExistence(timeout: 5))
    }

    func testWelcomeDoesNotReturnAfterItHasBeenDismissed() {
        let app = XCUIApplication.launchedAsNewUser()
        app.expect(app.buttons[A11yUI.Onboarding.welcomeSkip]).tap()
        app.expect(app.tab(A11yUI.Tab.today))

        // Relaunch without the reset flag: a returning user must not be welcomed again.
        app.terminate()
        app.launchArguments.removeAll { $0 == "-offrent-reset-onboarding" }
        app.launch()

        XCTAssertTrue(app.tab(A11yUI.Tab.today).waitForExistence(timeout: 8))
        XCTAssertFalse(
            app.otherElements[A11yUI.Onboarding.welcomeRoot].exists,
            "the welcome came back for somebody who had already dismissed it"
        )
    }

    /// The hands-on half. The bar has to appear *in* the app — over it would defeat the point,
    /// since it is telling somebody which control to tap.
    func testTheTourContinuesIntoAWalkthroughThatCanBeLeft() {
        let app = XCUIApplication.launchedAsNewUser()

        app.expect(app.buttons[A11yUI.Onboarding.welcomeTour]).tap()
        app.expect(app.otherElements[A11yUI.Onboarding.tourRoot])
        for _ in 1...4 {
            app.expect(app.buttons[A11yUI.Onboarding.tourNext], timeout: 5).tap()
        }
        app.expect(app.buttons[A11yUI.Onboarding.continueTour]).tap()

        XCTAssertTrue(
            app.tab(A11yUI.Tab.today).waitForExistence(timeout: 5),
            "the walkthrough runs inside the app, not as another full-screen wall"
        )
        app.expect(app.otherElements[A11yUI.Onboarding.guideBar])
        XCTAssertTrue(
            app.buttons[A11yUI.Onboarding.guideAction].exists,
            "the first step must offer a way to open Add rental"
        )

        app.buttons[A11yUI.Onboarding.guideSkip].tap()
        XCTAssertFalse(
            app.otherElements[A11yUI.Onboarding.guideBar].exists,
            "skipping the walkthrough must end it, not hide it until next launch"
        )
    }

    func testAddYourFirstRentalOpensTheForm() {
        let app = XCUIApplication.launchedAsNewUser()

        app.expect(app.buttons[A11yUI.Onboarding.welcomeAddRental]).tap()
        XCTAssertTrue(
            app.textFields[A11yUI.AddRental.equipmentName].waitForExistence(timeout: 8),
            "the welcome's primary action must open the form it names"
        )
    }
}
