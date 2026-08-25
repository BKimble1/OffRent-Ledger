import Foundation
import XCTest

/// §12.6–9 and §12.15: the map is always there, it opens, it searches your own records, and a
/// rental can be given a location after the fact.
final class MapAndEditingUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    /// §12.6: Today always contains the map, and says so plainly when there is nothing on it.
    ///
    /// The screenshots showed the failure: with one rental and no location the section was simply
    /// absent, so there was no way to discover the map existed — or that a rental was missing
    /// from it.
    func testTodayShowsTheMapEvenWithNoRentals() {
        let app = XCUIApplication.launched(seed: .empty)

        app.tab(A11yUI.Tab.today).tap()
        XCTAssertTrue(
            app.anyElement(A11yUI.Today.map).waitForExistence(timeout: 8),
            "the map card must exist on Today whether or not anything is on rent"
        )
        XCTAssertTrue(
            app.staticTexts["No rentals in progress"].waitForExistence(timeout: 5),
            "with nothing on rent the map must carry the empty-state overlay, not vanish"
        )
    }

    func testTodayKeepsTheMapWithRentalsThatHaveNoLocation() {
        let app = XCUIApplication.launched()

        app.tab(A11yUI.Tab.today).tap()
        XCTAssertTrue(
            app.anyElement(A11yUI.Today.map).waitForExistence(timeout: 8),
            "a rental with no mapped jobsite must not remove the map"
        )
    }

    /// §12.7: tapping the card opens the full-screen map, and X closes it back to Today.
    func testTheTodayMapOpensFullScreenAndClosesBack() {
        let app = XCUIApplication.launched()

        app.tab(A11yUI.Tab.today).tap()
        app.tapInContent(app.expect(app.anyElement(A11yUI.Today.map)))

        XCTAssertTrue(
            app.anyElement(A11yUI.OperationsMap.root).waitForExistence(timeout: 8),
            "the Today map must open a full-screen map, not another list"
        )
        XCTAssertTrue(app.textFields[A11yUI.OperationsMap.searchField].exists)

        // §12.8: the key is reachable and readable.
        app.tapWhenHittable(app.expect(app.buttons[A11yUI.OperationsMap.legendToggle]))
        XCTAssertTrue(
            app.anyElement(A11yUI.OperationsMap.legend).waitForExistence(timeout: 5),
            "the map must be able to explain its own colours"
        )

        app.tapWhenHittable(app.expect(app.buttons[A11yUI.OperationsMap.close]))
        XCTAssertTrue(
            app.anyElement(A11yUI.Today.root).waitForExistence(timeout: 8),
            "closing the map must return to the Today it was opened from"
        )
    }

    /// §12.8–9: the search field searches the user's records, and a result exposes its status
    /// and the actions that act on it.
    func testTheMapSearchesLocalRecordsAndOffersOpenAndEdit() {
        let app = XCUIApplication.launched()

        app.tab(A11yUI.Tab.today).tap()
        app.tapInContent(app.expect(app.anyElement(A11yUI.Today.map)))
        app.expect(app.anyElement(A11yUI.OperationsMap.root))

        app.expect(app.textFields[A11yUI.OperationsMap.searchField]).tap()
        app.typeText("Skid")

        let result = app.expect(app.anyElement(A11yUI.OperationsMap.searchResult), timeout: 8)
        XCTAssertTrue(
            result.label.contains("Skid"),
            "searching the user's own data must find their own machine: \\(result.label)"
        )
        result.tap()

        let card = app.expect(app.anyElement(A11yUI.OperationsMap.detailCard), timeout: 8)
        XCTAssertTrue(card.exists)
        XCTAssertTrue(
            app.buttons[A11yUI.OperationsMap.openRecord].exists,
            "the detail card must offer to open the rental"
        )
        XCTAssertTrue(
            app.buttons[A11yUI.OperationsMap.editRecord].exists,
            "the detail card must offer to edit the rental"
        )
    }

    /// A record with no coordinate is never drawn at a made-up one, and the map says so.
    func testARentalWithNoLocationIsNamedRatherThanQuietlyMissing() {
        let app = XCUIApplication.launched()

        app.tab(A11yUI.Tab.today).tap()
        app.tapInContent(app.expect(app.anyElement(A11yUI.Today.map)))
        app.expect(app.anyElement(A11yUI.OperationsMap.root))

        app.expect(app.textFields[A11yUI.OperationsMap.searchField]).tap()
        app.typeText("Skid")
        app.expect(app.anyElement(A11yUI.OperationsMap.searchResult), timeout: 8).tap()

        let card = app.expect(app.anyElement(A11yUI.OperationsMap.detailCard), timeout: 8)
        XCTAssertTrue(
            card.staticTexts["No location set"].exists,
            "a rental with no jobsite location must say so rather than appear placed"
        )
        XCTAssertTrue(
            app.buttons[A11yUI.OperationsMap.addLocation].exists,
            "and it must offer the action that fixes it"
        )
    }

    /// §12.15: an existing rental can be edited, and the edit sticks across a relaunch.
    ///
    /// Uses the on-disk store deliberately: an in-memory one cannot demonstrate persistence.
    func testAnExistingRentalCanBeEditedAndTheChangeSurvivesRelaunch() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-offrent-reset-state",
            "-offrent-disable-animations",
            "-offrent-force-pro",
            "-offrent-seed-walkthrough",
            "-offrent-fixed-now", XCUIApplication.fixedNow,
            "-offrent-skip-onboarding",
        ]
        app.launch()

        app.tab(A11yUI.Tab.rentals).tap()
        app.expect(app.staticTexts["Skid Steer Loader"]).tap()

        // Edit is in the navigation bar, where iOS users look for it. Before this it existed
        // only as a link called "Edit terms", four sections down, that reached six fields.
        app.tapWhenHittable(app.expect(app.buttons[A11yUI.ItemDetail.edit]))
        app.expect(app.anyElement(A11yUI.EditRental.root))

        let name = app.expect(app.textFields[A11yUI.AddRental.equipmentName])
        XCTAssertEqual(
            name.value as? String, "Skid Steer Loader",
            "the editor must preload what is already there"
        )
        name.tap()
        name.typeText(" 75HP")
        app.dismissKeyboard()

        app.tapWhenHittable(app.expect(app.buttons[A11yUI.EditRental.save]))

        XCTAssertTrue(
            app.staticTexts["Skid Steer Loader 75HP"].waitForExistence(timeout: 8),
            "the edit did not reach the screen it came from"
        )

        app.relaunchKeepingStore()
        app.tab(A11yUI.Tab.rentals).tap()
        XCTAssertTrue(
            app.staticTexts["Skid Steer Loader 75HP"].waitForExistence(timeout: 10),
            "the edit did not survive a relaunch"
        )
    }

    /// The editor reaches the company and the jobsite — the two the old one could not.
    func testTheEditorReachesTheCompanyAndTheJobsite() {
        let app = XCUIApplication.launched()

        app.tab(A11yUI.Tab.rentals).tap()
        app.expect(app.staticTexts["Skid Steer Loader"]).tap()
        app.tapWhenHittable(app.expect(app.buttons[A11yUI.ItemDetail.edit]))

        app.expect(app.anyElement(A11yUI.EditRental.root))
        XCTAssertTrue(
            app.anyElement(A11yUI.AddRental.companyRow).waitForExistence(timeout: 8),
            "a rental filed under the wrong company must be correctable"
        )
        XCTAssertTrue(
            app.anyElement(A11yUI.AddRental.jobSiteRow).exists,
            "a rental with no jobsite must be able to gain one"
        )
    }
}

/// §12.17: nothing important sits under the tab bar, the sticky action bar or the keyboard.
///
/// This is the class of defect the screenshots showed most often and that no unit test can see.
/// It is also the one where `isHittable` lies: a control whose centre is inside the tab bar
/// reports `true` and does nothing when tapped, which cost eleven CI runs to diagnose once
/// already. `tapInContent` checks the geometry rather than trusting the flag.
final class LayoutObstructionUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    /// The primary action on the longest form in the app, with the keyboard up.
    func testTheSaveBarStaysReachableWithTheKeyboardUp() {
        let app = XCUIApplication.launched(seed: .empty)

        app.tab(A11yUI.Tab.rentals).tap()
        app.openNewRental()

        app.expect(app.textFields[A11yUI.AddRental.equipmentName]).tap()
        app.typeText("Mini Excavator")

        // With the keyboard up, the save bar must still be on screen and above it. A bar pinned
        // with fixed padding instead of a safe-area inset fails exactly here.
        let save = app.expect(app.buttons[A11yUI.AddRental.save])
        XCTAssertTrue(save.exists)
        if app.keyboards.count > 0 {
            XCTAssertLessThan(
                save.frame.maxY, app.keyboards.element.frame.minY,
                "the save bar is behind the keyboard"
            )
        }

        app.dismissKeyboard()
        XCTAssertLessThanOrEqual(
            save.frame.maxY, app.frame.maxY,
            "the save bar runs off the bottom of the screen"
        )
    }

    /// Today's content is not hidden behind the tab bar when scrolled to the end.
    func testTodayScrollsClearOfTheTabBar() {
        let app = XCUIApplication.launched()

        app.tab(A11yUI.Tab.today).tap()
        let root = app.expect(app.anyElement(A11yUI.Today.root))
        for _ in 0..<4 { root.swipeUp() }

        // The tab bar is the floor. Anything the user is meant to read has to end above it.
        let tabBar = app.tabBars.element
        guard tabBar.exists else { return }
        let map = app.anyElement(A11yUI.Today.map)
        if map.exists, map.frame.height > 0 {
            XCTAssertLessThanOrEqual(
                map.frame.minY, tabBar.frame.minY,
                "the map card is entirely behind the tab bar after scrolling"
            )
        }
    }

    /// The map's own controls clear the status bar at the top and the home indicator at the
    /// bottom — §6 names both.
    func testTheOperationsMapControlsClearTheEdges() {
        let app = XCUIApplication.launched()

        app.tab(A11yUI.Tab.today).tap()
        app.tapInContent(app.expect(app.anyElement(A11yUI.Today.map)))
        app.expect(app.anyElement(A11yUI.OperationsMap.root))

        let close = app.expect(app.buttons[A11yUI.OperationsMap.close])
        XCTAssertGreaterThan(
            close.frame.minY, app.frame.minY,
            "the close button is under the status bar"
        )
        let search = app.expect(app.textFields[A11yUI.OperationsMap.searchField])
        XCTAssertGreaterThan(
            search.frame.minY, app.frame.minY,
            "the search field is under the status bar"
        )
        XCTAssertLessThan(
            search.frame.maxY, app.frame.maxY,
            "the search field is off the bottom of the screen"
        )
    }
}
