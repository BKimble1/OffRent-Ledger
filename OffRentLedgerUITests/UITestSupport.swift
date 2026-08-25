import Foundation
import XCTest

/// Shared launch and navigation helpers.
///
/// Every launch is deterministic by construction: an in-memory store, a frozen clock, a stubbed
/// recogniser and animations off. A UI test that depends on today's date is a test that fails on
/// the first of the month.
extension XCUIApplication {

    /// 9 May 2026, 10:00 UTC. Five days after the fixture's delivery date, so the walkthrough
    /// rental is mid-flight and its estimate is a known figure.
    static let fixedNow = "2026-05-09T15:00:00Z"

    static func launched(
        seed: Seed = .walkthrough,
        entitlement: Entitlement = .pro
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-offrent-in-memory-store",
            "-offrent-reset-state",
            "-offrent-disable-animations",
            "-offrent-stub-ocr",
            "-offrent-fixed-now", fixedNow,
            // Every existing scenario starts as a returning user. Without this the welcome sits
            // in front of all eleven of them and none of them can see the app.
            "-offrent-skip-onboarding",
        ]
        app.launchArguments += seed.arguments
        app.launchArguments += entitlement.arguments
        app.launch()
        return app
    }

    /// A first run, with the welcome screen showing.
    static func launchedAsNewUser() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-offrent-in-memory-store",
            "-offrent-reset-state",
            "-offrent-disable-animations",
            "-offrent-stub-ocr",
            "-offrent-fixed-now", fixedNow,
            "-offrent-reset-onboarding",
        ]
        app.launch()
        return app
    }

    enum Seed {
        case empty
        case walkthrough
        case freeLimit

        var arguments: [String] {
            switch self {
            case .empty: []
            case .walkthrough: ["-offrent-seed-walkthrough"]
            case .freeLimit: ["-offrent-seed-free-limit"]
            }
        }
    }

    enum Entitlement {
        case pro
        case free

        var arguments: [String] {
            switch self {
            case .pro: ["-offrent-force-pro"]
            case .free: ["-offrent-force-free"]
            }
        }
    }

    func tab(_ identifier: String) -> XCUIElement { tabBars.buttons[identifier] }

    /// An element addressed by its identifier, whatever type UIKit chose to back it with.
    ///
    /// Use this where the element type is the platform's decision rather than the app's: a `Form`
    /// or `ScrollView` serving as a screen root, or a `List` row whose identifier lands on the
    /// row's button rather than on its cell. Where the app deliberately builds an accessibility
    /// container, keep asserting `otherElements` instead — that is the thing under test, and a
    /// loose query here would have hidden the first run of these tests finding three separate
    /// buttons all wearing the welcome screen's own identifier.
    func anyElement(_ identifier: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Waits for an element and, when it never arrives, says what was on screen instead.
    ///
    /// The previous version put `element.identifier` in the failure message. Reading that
    /// property on an element that does not exist throws its own "failed to get matching
    /// snapshot" error, so every timeout in this suite was reported as a snapshot failure and the
    /// message never printed. What is actually needed is the other side of the question — not
    /// "which identifier was missing" but "what is on this screen, and as what type".
    @discardableResult
    func expect(
        _ element: XCUIElement,
        timeout: TimeInterval = 8,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        if !element.waitForExistence(timeout: timeout) {
            // Deliberately nothing about `element` in this message. Every property that would
            // name it — `identifier`, `label`, even `description` — resolves a snapshot, and
            // resolving a snapshot for an element that does not exist throws the error that hid
            // this diagnosis in the first place. The file and line say which call it was.
            XCTFail(
                """
                element did not appear within \(timeout)s.
                Identified elements on screen:
                \(identifiedElements())
                """,
                file: file, line: line
            )
        }
        return element
    }

    /// Every element currently on screen that carries an accessibility identifier, with its type.
    ///
    /// A full `debugDescription` of a busy screen runs to several hundred lines of unnamed
    /// containers; these are the lines that decide whether a test is looking for the right thing.
    func identifiedElements() -> String {
        let lines = debugDescription
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains("identifier: '") }
        return lines.isEmpty ? "(none — the app may not have finished launching)"
                             : lines.joined(separator: "\n")
    }

    /// Pops one screen off the current navigation stack.
    func back() {
        let backButton = navigationBars.buttons["BackButton"]
        if backButton.exists { backButton.tap(); return }
        navigationBars.buttons.element(boundBy: 0).tap()
    }

    /// Waits for a control and taps it.
    ///
    /// For controls that belong where they are drawn: a pinned bottom bar, a navigation bar, a
    /// sheet's toolbar. Being at the edge of the screen is correct for those, and the only
    /// question is whether they have arrived yet.
    func tapWhenHittable(
        _ element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard element.waitForExistence(timeout: 8) else {
            XCTFail(
                """
                element never appeared, so it could not be tapped.
                Identified elements on screen:
                \(identifiedElements())
                """,
                file: file, line: line
            )
            return
        }
        element.tap()
    }

    /// Scrolls a control that lives in scrollable content until it is clear of the bars at the
    /// edges of the screen, then taps it.
    ///
    /// `isHittable` is not enough on its own, which a run proved: "Record a follow-up" sat at
    /// y 779–823 on an 874-point screen with the tab bar starting at 795, so its centre was
    /// inside the tab bar — and `isHittable` still returned true. The tap went to the
    /// already-selected Audit tab, which does nothing visible, so the screen looked untouched.
    ///
    /// Only for content that scrolls. A control pinned to the bottom of a screen can never come
    /// clear of the bottom of the screen, and asking it to is how the previous version of this
    /// failed on the Save bar.
    func tapInContent(
        _ element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard element.waitForExistence(timeout: 8) else {
            XCTFail(
                """
                element never appeared, so it could not be tapped.
                Identified elements on screen:
                \(identifiedElements())
                """,
                file: file, line: line
            )
            return
        }
        let clearOfBottom = frame.height * 0.82
        let clearOfTop = frame.height * 0.15
        for _ in 0..<6 {
            let box = element.frame
            let tooLow = box.maxY > clearOfBottom
            let tooHigh = box.minY < clearOfTop
            if !tooLow, !tooHigh, element.isHittable {
                element.tap()
                return
            }
            if tooLow { swipeUp() } else { swipeDown() }
        }
        XCTFail(
            """
            element never came clear of the bars at the edges of the screen.
            Identified elements on screen:
            \(identifiedElements())
            """,
            file: file, line: line
        )
    }

    /// Dismisses the keyboard through the app's own Done affordance, if one is up.
    ///
    /// A decimal pad has no return key, which is why `CurrencyField` puts Done in the keyboard
    /// toolbar. A test that skips it leaves half the sheet covered: XCUITest will happily
    /// synthesise a tap at a control's centre while the keyboard is over that point, the tap
    /// lands on a key, and the button the test meant to press never fires.
    func dismissKeyboard() {
        guard keyboards.count > 0 else { return }
        for candidate in [toolbars.buttons["Done"], keyboards.buttons["Done"]] where candidate.exists {
            candidate.tap()
            return
        }
    }

    /// Turns a toggle on and proves it took.
    ///
    /// A `Toggle` in a `Form` is a single accessibility element spanning the whole row, so
    /// XCUITest taps the middle of it — which is the label, not the switch. That toggles the row
    /// in most cases and quietly does nothing in some, and a switch that silently failed to move
    /// shows up several steps later as a Save button that is still disabled.
    func setOn(
        _ toggle: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard toggle.waitForExistence(timeout: 8) else {
            XCTFail(
                "toggle did not appear.\nIdentified elements on screen:\n\(identifiedElements())",
                file: file, line: line
            )
            return
        }
        if toggle.value as? String == "1" { return }
        toggle.tap()
        if toggle.value as? String != "1" {
            let innerSwitch = toggle.switches.firstMatch
            if innerSwitch.exists { innerSwitch.tap() }
        }
        XCTAssertEqual(
            toggle.value as? String, "1",
            """
            the toggle did not turn on after being tapped.
            Identified elements on screen:
            \(identifiedElements())
            """,
            file: file, line: line
        )
    }

    /// Relaunches with the same arguments, keeping the in-memory store alive is impossible — so
    /// persistence tests use the on-disk store instead. See `RelaunchPersistenceTests`.
    func relaunchKeepingStore() {
        terminate()
        launchArguments.removeAll { $0 == "-offrent-in-memory-store" || $0 == "-offrent-reset-state" }
        launchArguments.removeAll { $0.hasPrefix("-offrent-seed") }
        launch()
    }
}

// MARK: - Robots for the flows that changed shape

extension XCUIApplication {

    /// A menu item, addressed however UIKit chose to expose it.
    ///
    /// SwiftUI builds a `Menu`'s contents into a `UIMenu` of `UIAction`s, and an accessibility
    /// identifier set on the `Button` does not reliably survive that translation — the element
    /// that appears in the tree is usually addressed by its visible title, and it may be a
    /// `button` or a `menuItem` depending on the presentation. Every form is tried rather than
    /// one being guessed at, because guessing wrong here is a timeout that names nothing.
    func menuItem(_ identifier: String, titled title: String) -> XCUIElement {
        for candidate in [
            buttons[identifier],
            menuItems[identifier],
            buttons[title],
            menuItems[title],
            descendants(matching: .any).matching(identifier: identifier).firstMatch,
        ] where candidate.exists {
            return candidate
        }
        // Nothing exists yet. Return the most likely one so `expect` can wait on it and report
        // the screen's real contents if it never arrives.
        return buttons[title]
    }

    /// Opens New Rental from the Rentals tab.
    ///
    /// The plus is a menu now — New Rental, New Rental Company, New Jobsite — so reaching the
    /// form is two taps rather than one. Wrapped here so that the twelve tests which only want
    /// to get to the form do not each encode the menu's shape.
    func openNewRental() {
        tapWhenHittable(expect(buttons[A11yUI.Rentals.addMenu]))
        tapWhenHittable(expect(menuItem(A11yUI.Rentals.addRental, titled: "New rental")))
    }

    /// The same, for the two records the menu can also create.
    func openNewCompanyFromMenu() {
        tapWhenHittable(expect(buttons[A11yUI.Rentals.addMenu]))
        tapWhenHittable(expect(menuItem(A11yUI.Rentals.addCompany, titled: "New rental company")))
    }

    func openNewJobsiteFromMenu() {
        tapWhenHittable(expect(buttons[A11yUI.Rentals.addMenu]))
        tapWhenHittable(expect(menuItem(A11yUI.Rentals.addJobSite, titled: "New jobsite")))
    }

    /// Creates a rental company from inside a rental draft and returns to the draft with it
    /// selected.
    ///
    /// This is the §3 requirement expressed as a helper: `Add New` inside the picker opens the
    /// same editor the Rentals plus menu opens, and saving comes back to the draft rather than
    /// discarding it.
    func addCompanyFromDraft(named name: String) {
        tapInContent(expect(anyElement(A11yUI.AddRental.companyRow)))
        tapWhenHittable(expect(buttons[A11yUI.Company.addNew]))
        expect(textFields[A11yUI.Company.name]).tap()
        typeText(name)
        dismissKeyboard()
        tapWhenHittable(expect(buttons[A11yUI.Company.save]))
    }

    /// Fills in the minimum a rental needs: a machine, a company, a daily rate.
    func fillMinimalRental(equipment: String, company: String, dailyRate: String) {
        expect(textFields[A11yUI.AddRental.equipmentName]).tap()
        typeText(equipment)
        dismissKeyboard()

        addCompanyFromDraft(named: company)

        tapInContent(expect(textFields[A11yUI.AddRental.dailyRate]))
        typeText(dailyRate)
        dismissKeyboard()
    }
}
