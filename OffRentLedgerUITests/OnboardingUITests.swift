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

    /// §12.16: the whole walkthrough, using only Next and Finish.
    ///
    /// The guide this replaced could not be finished at all without creating a rental, ringing a
    /// rental company, recording a pickup and accepting an invoice — none of which a person has
    /// on the day they install the app. So the two properties asserted here are the two that
    /// were missing: it ends, and it writes nothing.
    func testTheWalkthroughCompletesOnItsOwnControlsAndCreatesNothing() {
        let app = XCUIApplication.launchedAsNewUser()

        app.expect(app.buttons[A11yUI.Onboarding.welcomeTour]).tap()
        app.expect(app.otherElements[A11yUI.Onboarding.tourRoot])

        // Next until the button says Finish. Driven by the label rather than a hard-coded count,
        // so adding a page does not silently strand this test halfway.
        let forward = app.buttons[A11yUI.Onboarding.tourNext]
        for step in 1...12 {
            app.expect(forward, timeout: 5)
            if forward.label == "Finish" { break }
            forward.tap()
            XCTAssertTrue(
                app.otherElements[A11yUI.Onboarding.tourRoot].exists,
                "the walkthrough closed itself on step \(step); only Finish may end it"
            )
        }
        XCTAssertEqual(forward.label, "Finish", "the walkthrough never reached a last page")
        forward.tap()

        // Finish dismisses on its own. Nothing else to tap, nothing to swipe away.
        XCTAssertTrue(
            app.anyElement(A11yUI.Today.root).waitForExistence(timeout: 5),
            "Finish must dismiss the walkthrough and land on Today"
        )
        XCTAssertFalse(
            app.otherElements[A11yUI.Onboarding.tourRoot].exists,
            "the walkthrough was still on screen after Finish"
        )

        // And it created nothing. Today's empty state is only drawn when there are no rentals,
        // and the Rentals tab says so in its own words.
        XCTAssertTrue(
            app.anyElement(A11yUI.Today.emptyState).waitForExistence(timeout: 5),
            "the walkthrough put a rental in the user's store"
        )
        app.tab(A11yUI.Tab.rentals).tap()
        XCTAssertTrue(
            app.staticTexts["No rentals yet"].waitForExistence(timeout: 5),
            "the walkthrough created a rental"
        )
        app.tapInContent(app.expect(app.buttons[A11yUI.Rentals.companiesLink]))
        XCTAssertTrue(
            app.staticTexts["No rental companies yet"].waitForExistence(timeout: 5),
            "the walkthrough created a rental company"
        )
        app.back()
        app.tapInContent(app.expect(app.buttons[A11yUI.Rentals.jobSitesLink]))
        XCTAssertTrue(
            app.staticTexts["No jobsites yet"].waitForExistence(timeout: 5),
            "the walkthrough created a jobsite"
        )
    }

    /// Back works, and the walkthrough does not come back once it has been finished.
    func testTheWalkthroughGoesBackwardsAndIsNotShownTwice() {
        let app = XCUIApplication.launchedAsNewUser()

        app.expect(app.buttons[A11yUI.Onboarding.welcomeTour]).tap()
        app.expect(app.otherElements[A11yUI.Onboarding.tourRoot])

        XCTAssertFalse(
            app.buttons[A11yUI.Onboarding.tourBack].exists,
            "Back is absent on the first page rather than present and dead"
        )
        app.expect(app.buttons[A11yUI.Onboarding.tourNext]).tap()
        app.expect(app.buttons[A11yUI.Onboarding.tourBack]).tap()
        XCTAssertFalse(
            app.buttons[A11yUI.Onboarding.tourBack].exists,
            "Back from page two must return to page one"
        )

        app.expect(app.buttons[A11yUI.Onboarding.tourSkip]).tap()
        app.expect(app.anyElement(A11yUI.Today.root))

        app.terminate()
        app.launchArguments.removeAll { $0 == "-offrent-reset-onboarding" }
        app.launch()
        XCTAssertTrue(app.tab(A11yUI.Tab.today).waitForExistence(timeout: 8))
        XCTAssertFalse(
            app.otherElements[A11yUI.Onboarding.tourRoot].exists,
            "a walkthrough that reappears after being skipped has stopped being optional"
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
