import Foundation
import XCTest

/// A short accessibility smoke pass. Not a substitute for the manual VoiceOver walkthrough in
/// RELEASE_CHECKLIST.md §2, which is a device gate.
///
/// Executed in CI on a booted simulator. Green at `b3057d1`; see TEST_MATRIX.md section C.
final class AccessibilityUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    func testEveryTabIsReachableAndLabelled() {
        let app = XCUIApplication.launched()
        for identifier in [
            A11yUI.Tab.today, A11yUI.Tab.rentals, A11yUI.Tab.audit, A11yUI.Tab.settings,
        ] {
            let tab = app.tab(identifier)
            XCTAssertTrue(tab.exists, "missing tab: \(identifier)")
            tab.tap()
            XCTAssertFalse(tab.label.isEmpty, "tab has no label: \(identifier)")
        }
    }

    func testTodayShowsTheEstimateLabelledAsAnEstimate() {
        let app = XCUIApplication.launched()
        let estimate = app.expect(app.staticTexts[A11yUI.Today.estimatedRentRunning])
        XCTAssertTrue(
            estimate.label.lowercased().contains("estimated"),
            "the accessibility label must say the figure is an estimate, not just show a number"
        )
    }

    func testTheDisclosureIsAnAccessibilityElementWithItsFullText() {
        let app = XCUIApplication.launched()
        app.tab(A11yUI.Tab.rentals).tap()
        app.openRental(named: "Skid Steer Loader")
        app.expect(app.buttons[A11yUI.ItemDetail.markDone]).tap()

        // A StaticText, not an Other: the banner combines its symbol and its sentence into one
        // element, and XCUITest reports a combined element backed by a UILabel as static text.
        // The assertion below is the point of the test either way — one element, whole sentence.
        let disclosure = app.expect(app.staticTexts[A11yUI.ItemDetail.disclosure])
        XCTAssertTrue(disclosure.label.contains("does not notify the rental company"))
    }

    func testStatusIsAnnouncedAsTextNotOnlyAsColour() {
        let app = XCUIApplication.launched()
        app.tab(A11yUI.Tab.rentals).tap()
        app.openRental(named: "Skid Steer Loader")

        let status = app.expect(app.otherElements[A11yUI.ItemDetail.status])
        XCTAssertTrue(status.label.hasPrefix("Status:"), "status must be spoken, not only tinted")
    }
}
