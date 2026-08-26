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

    /// A tab-bar button, resolved to exactly one element.
    ///
    /// iPadOS 18 draws the tab bar as a floating control at the top of the window, and XCUITest
    /// reports more than one element for a single tab. The subscript form does not care: `exists`
    /// is true for a query with two matches, and the failure lands on the *tap* instead —
    /// "Failed to tap \"Rentals\" Button: Find single matching element. Multiple matching
    /// elements found". That is every tab tap in the suite, and it took out all ten tests on the
    /// first iPad run, six of them in suites that had been green on iPhone for weeks.
    ///
    /// `element(boundBy:)` and `firstMatch` resolve to one element by construction, which is the
    /// whole fix. Preferring the one that is on screen is the other half: the second
    /// representation is present in the tree and not hittable, and tapping it does nothing at
    /// all — the failure mode this suite has already paid for twice.
    ///
    /// Matching identifier *or* label is what the subscript did. A `.tabItem` built from a
    /// `Label` carries its title in both, and the suite addresses tabs by title.
    func tab(_ identifier: String) -> XCUIElement {
        let named = NSPredicate(format: "identifier == %@ OR label == %@", identifier, identifier)
        if let inTabBar = firstOnScreen(tabBars.buttons.matching(named)) { return inTabBar }
        if let anywhere = firstOnScreen(buttons.matching(named)) { return anywhere }
        // Nothing has rendered yet. Hand back what the previous version returned, so a caller
        // that waits on it gets the old behaviour and the old failure message.
        return tabBars.buttons[identifier]
    }

    /// The first element of a query that is actually on screen, or the first that exists at all.
    ///
    /// Returns nil rather than an empty element so the caller can try somewhere else, and never
    /// returns the query itself — a query with two matches throws on `tap()`, which is the bug
    /// this exists to avoid.
    private func firstOnScreen(_ query: XCUIElementQuery) -> XCUIElement? {
        let count = query.count
        guard count > 0 else { return nil }
        for index in 0..<count {
            let candidate = query.element(boundBy: index)
            if candidate.exists, candidate.isHittable { return candidate }
        }
        return query.firstMatch
    }

    /// The frontmost scrollable container on screen, if there is one.
    ///
    /// `XCUIApplication.swipeUp()` swipes at the centre of the *window*. Where a sheet is up that
    /// point is usually inside it and the right thing happens — but a downward swipe on an iPad
    /// form sheet is also its dismiss gesture. `reveal` sweeps up eight times and then *down*
    /// twelve times looking for a row, so on an iPad it could throw the sheet away and then
    /// report, accurately and uselessly, that the element never appeared.
    ///
    /// Scrolling the container itself cannot dismiss anything, and it scrolls the thing the row
    /// is actually in rather than whatever happens to be under the middle of the screen.
    /// Searched back to front because the last match is the frontmost — the sheet, not the
    /// screen behind it.
    func scrollableContainer() -> XCUIElement? {
        for query in [collectionViews, tables, scrollViews] {
            let count = query.count
            guard count > 0 else { continue }
            for index in stride(from: count - 1, through: 0, by: -1) {
                let candidate = query.element(boundBy: index)
                if candidate.exists, candidate.isHittable { return candidate }
            }
        }
        return nil
    }

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
        // `firstOnScreen`, not the subscript, for the same reason as `tab`: an iPad can have
        // more than one navigation bar in the tree at once — a sheet's and the one behind it —
        // and a subscript that matches both throws on the tap rather than on the lookup.
        let named = NSPredicate(format: "identifier == %@ OR label == %@", "BackButton", "BackButton")
        if let backButton = firstOnScreen(navigationBars.buttons.matching(named)) {
            backButton.tap()
            return
        }
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
        // What is actually in the way, by its own frame.
        //
        // Two rounds of CI went into classifying the tab bar as "top" or "bottom" and applying a
        // band of reserved screen accordingly. Both were wrong, because the classification was
        // wrong: on an iPad the bar's container does not report where its contents are, and the
        // phone's fractions then got applied to a window laid out the other way up. The export
        // button sat at y 962 of an 1180-point window with nothing beneath it, was judged too
        // low, and was swiped at until the loop gave up.
        //
        // So this stops classifying. A control is in the way if it *overlaps* the element —
        // which needs no guess about which end of the screen anything is at, and is the actual
        // question. The tab bar is measured through its buttons, which have real frames on both
        // idioms; toolbars are included because a keyboard accessory bar is equally opaque.
        //
        // The original hazard is still covered, and more exactly than before: `isHittable`
        // returns true for a control whose centre is inside the tab bar, and an overlap test
        // rejects that before it can be tapped.
        func obstructions() -> [CGRect] {
            var boxes: [CGRect] = []
            for query in [tabBars.buttons, toolbars.buttons] {
                let count = query.count
                for index in 0..<count {
                    let candidate = query.element(boundBy: index)
                    if candidate.exists { boxes.append(candidate.frame) }
                }
            }
            return boxes
        }

        var lastBox = CGRect.zero
        var lastBlocker: CGRect?
        for _ in 0..<8 {
            let box = element.frame
            lastBox = box
            let scroller = scrollableContainer() ?? self

            // Off the screen entirely: bring it back before asking anything else about it.
            if box.maxY > frame.maxY { scroller.swipeUp(); continue }
            if box.minY < frame.minY { scroller.swipeDown(); continue }

            if let blocker = obstructions().first(where: { $0.intersects(box) }) {
                lastBlocker = blocker
                // Away from whatever is covering it, whichever end that is.
                if blocker.midY < box.midY { scroller.swipeDown() } else { scroller.swipeUp() }
                continue
            }
            lastBlocker = nil

            if element.isHittable {
                element.tap()
                return
            }

            // On screen, uncovered, and still not hittable. Wait once — something may be
            // animating — and if it is still saying no, tap the middle of it by coordinate.
            //
            // `isHittable` is not the authority here and this file already says so: it returns
            // *true* for a control whose centre is inside the tab bar, which is the failure this
            // helper was written after. It is equally capable of returning false for a control
            // that is plainly on screen and plainly not covered, and eight seconds of asking it
            // the same question is how the export button burned three rounds of CI.
            //
            // The geometry above has already established the thing this cares about: the element
            // is inside the window and no bar overlaps it. A tap at its centre is then exactly
            // what a person's finger would do, and a coordinate tap does not consult
            // `isHittable` or try to scroll first.
            _ = element.waitForExistence(timeout: 1)
            if element.isHittable {
                element.tap()
                return
            }
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return
        }

        XCTFail(
            """
            element never came clear of the bars at the edges of the screen.
            element \(lastBox), window \(frame)
            blocked by \(lastBlocker.map(String.init(describing:)) ?? "nothing")
            hittable \(element.isHittable)
            Identified elements on screen:
            \(identifiedElements())
            """,
            file: file, line: line
        )
    }

    /// Scrolls until an element that has not been rendered yet exists, then returns it.
    ///
    /// A `Form` builds its rows lazily. A row below the fold is not merely off-screen — it is
    /// **not in the accessibility tree at all**, so `expect` fails on existence eight seconds
    /// before `tapInContent` ever gets the chance to scroll to it. That is what the daily-rate
    /// field did: the dump showed equipment name, company, jobsite and the delivery date, and
    /// nothing at all for `addRental.dailyRate`, because the row had never been built.
    ///
    /// `tapInContent` scrolls an element that already exists into a clear part of the screen.
    /// This scrolls until it exists in the first place. The two compose: reveal, then tap.
    /// Which way to look first. A row that has never been built is below; one the form has
    /// already scrolled past is above. Both directions are tried either way — this only says
    /// which to spend the first few swipes on, which is eight seconds on the common path.
    enum RevealDirection { case below, above }

    @discardableResult
    func reveal(
        _ element: XCUIElement,
        searching direction: RevealDirection = .below,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        if element.exists { return element }
        // The container rather than the window — see `scrollableContainer`. Re-resolved on each
        // swipe because revealing a row can change which container is frontmost.
        let scroller = { self.scrollableContainer() ?? self }
        let first = direction == .below
            ? { scroller().swipeUp() } : { scroller().swipeDown() }
        let second = direction == .below
            ? { scroller().swipeDown() } : { scroller().swipeUp() }
        for _ in 0..<8 {
            first()
            if element.exists { return element }
        }
        // The other way, far enough to cross back over the whole screen and past it.
        for _ in 0..<12 {
            second()
            if element.exists { return element }
        }
        XCTFail(
            """
            element never appeared, even after scrolling the screen end to end.
            Identified elements on screen:
            \(identifiedElements())
            """,
            file: file, line: line
        )
        return element
    }

    /// Reveals a lazily built row and taps it.
    func revealAndTap(
        _ element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        reveal(element, file: file, line: line)
        tapInContent(element, file: file, line: line)
    }

    /// Dismisses the keyboard through the app's own Done affordance, if one is up.
    ///
    /// A decimal pad has no return key, which is why `CurrencyField` puts Done in the keyboard
    /// toolbar. A test that skips it leaves half the sheet covered: XCUITest will happily
    /// synthesise a tap at a control's centre while the keyboard is over that point, the tap
    /// lands on a key, and the button the test meant to press never fires.
    /// Puts the keyboard away, whatever kind it is.
    ///
    /// A decimal pad has no return key, which is why the app adds a `Done` toolbar to every
    /// currency field. A *text* keyboard has no `Done` — so the original version of this helper
    /// silently did nothing on the New Rental form, the keyboard stayed up, and the company row
    /// underneath the pinned Save bar could never be tapped. The failure surfaced several steps
    /// from its cause as "element never came clear of the bars".
    func dismissKeyboard() {
        guard keyboards.count > 0 else { return }

        // "Hide keyboard" is the iPad key — the one in the bottom-right corner of the software
        // keyboard. There is no equivalent on iPhone, so listing it costs an iPhone run nothing.
        let candidates = [
            toolbars.buttons["Done"],
            keyboards.buttons["Done"],
            keyboards.buttons["Hide keyboard"],
        ]
        for candidate in candidates where candidate.exists && candidate.isHittable {
            tapWithoutScrolling(candidate)
            if keyboards.count == 0 { return }
        }

        // A text keyboard's return key. Its label follows `submitLabel`, so every plausible one
        // is tried rather than assuming "return".
        for label in ["Return", "return", "Next", "next", "Done", "Search", "Go"] {
            let key = keyboards.buttons[label]
            if key.exists, key.isHittable {
                tapWithoutScrolling(key)
                if keyboards.count == 0 { return }
            }
        }

        // Last resort: the form scrolls the keyboard away. `scrollDismissesKeyboard` is on the
        // rental form for exactly this reason, and it is the gesture a person would use.
        swipeDown()
    }

    /// Taps an element at its centre without asking the accessibility layer to scroll it in first.
    ///
    /// `XCUIElement.tap()` scrolls to visible before tapping. On an iPad the software keyboard's
    /// accessibility frames can sit below the bottom of the window — a Return key reported at
    /// y 1251 in an 1180-point window — and that scroll fails the whole test with
    /// `kAXErrorCannotComplete performing AXAction kAXScrollToVisibleAction`. It took out both
    /// of the tests that got as far as typing on the first iPad run that reached that point.
    ///
    /// A coordinate tap has no scroll step. It is deliberately narrow: keyboard keys and the
    /// bars above them, never app content, where the scroll is the useful half of `tap()`.
    private func tapWithoutScrolling(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
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
        // A short wait, then `reveal`. A `Toggle` in a `Form` is built lazily, so a row below
        // the fold does not exist to be waited for — and on an iPad the confirmation sheet is a
        // 650-point form sheet where the affirmation is exactly that. Waiting eight seconds for
        // a row that had never been built is what "toggle did not appear" meant there.
        //
        // On an iPhone the row is already on screen, `waitForExistence` returns at once, and
        // `reveal` is never reached.
        if !toggle.waitForExistence(timeout: 3) {
            reveal(toggle, file: file, line: line)
        }
        guard toggle.exists else {
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
        // Every lookup resolves to a single element. A `Menu` on an iPad opens in a popover and
        // the tree can carry both the popover's copy and the source button, which makes a bare
        // subscript ambiguous — and an ambiguous element fails on `tap()`, several steps after
        // the place that would explain it.
        let byIdentifier = NSPredicate(format: "identifier == %@", identifier)
        let byTitle = NSPredicate(format: "identifier == %@ OR label == %@", title, title)
        // Typed explicitly: the last entry is non-optional and the rest are not, and an array
        // literal that has to reconcile the two is a needless thing to make the compiler guess.
        let candidates: [XCUIElement?] = [
            firstOnScreen(buttons.matching(byIdentifier)),
            firstOnScreen(menuItems.matching(byIdentifier)),
            firstOnScreen(buttons.matching(byTitle)),
            firstOnScreen(menuItems.matching(byTitle)),
            descendants(matching: .any).matching(identifier: identifier).firstMatch,
        ]
        for candidate in candidates {
            guard let candidate, candidate.exists else { continue }
            return candidate
        }
        // Nothing exists yet. Return the most likely one so `expect` can wait on it and report
        // the screen's real contents if it never arrives.
        return buttons[title]
    }

    /// Opens a rental from the Rentals list by its equipment name.
    ///
    /// Not `app.staticTexts[name].tap()`, which is what every test here used to do and what
    /// broke the moment a second screen carried the same words. A row is a *combined*
    /// accessibility element whose label is the whole row, Today's upcoming-rate-change row
    /// carries the same equipment name, and a bare label lookup that matches two elements fails
    /// on the tap rather than on the wait — reporting "multiple matching elements" and naming
    /// neither of them.
    ///
    /// Scoped to the rentals list and matched on a label prefix, so it addresses one row on one
    /// screen and says which if it cannot find it.
    func openRental(named name: String, file: StaticString = #filePath, line: UInt = #line) {
        let list = anyElement(A11yUI.Rentals.root)
        // Not a `guard` that fails. The absence of the list's own identifier is worth knowing
        // about but is not on its own a reason to give up: the row lookup below can still find
        // the row unscoped, and reporting "the rentals list never appeared" while the rentals
        // list was plainly on screen is how eleven tests once named the wrong defect.
        let scoped = list.waitForExistence(timeout: 8)
        let prefix = NSPredicate(format: "label BEGINSWITH %@", name)
        // The scoped queries first, then the unscoped one this replaced. Scoping is what
        // keeps it off Today's upcoming-rate-change row, which carries the same equipment
        // name — but if the scope itself is ever wrong, falling back to the lookup that was
        // green at b3057d1 turns a silent eight-second timeout into a passing test.
        var queries = [buttons, staticTexts]
        if scoped { queries = [list.buttons, list.staticTexts, list.cells] + queries }
        for query in queries {
            let row = query.matching(prefix).firstMatch
            if row.waitForExistence(timeout: 4) {
                tapInContent(row, file: file, line: line)
                return
            }
        }
        XCTFail(
            "no row in the rentals list begins with “\(name)”.\n\(identifiedElements())",
            file: file, line: line
        )
    }

    /// Whether a rental with this name is on screen — as a list row, or as the title of its own
    /// screen.
    ///
    /// A rentals row is one combined accessibility element whose label is the entire row:
    /// equipment, reference, company, status and running estimate. So `staticTexts["Mini
    /// Excavator"]` is not what a row looks like, and a test that asserts it is asserting
    /// something about a screen it is not on. Matched on a label prefix across both types
    /// instead, which holds for the row and for the navigation title alike.
    func rentalIsListed(_ name: String, timeout: TimeInterval = 10) -> Bool {
        let prefix = NSPredicate(format: "label BEGINSWITH %@", name)
        let row = buttons.matching(prefix).firstMatch
        let title = staticTexts.matching(prefix).firstMatch
        if row.exists || title.exists { return true }
        if row.waitForExistence(timeout: timeout) { return true }
        return title.exists
    }

    /// Opens an invoice from the Audit list, addressed by the company on its row.
    ///
    /// Scoped to the Audit list for the same reason `openRental` is scoped to the rentals one:
    /// the company name appears on a rental row too, and an unscoped lookup finds whichever the
    /// tree happens to order first.
    func openInvoice(from company: String, file: StaticString = #filePath, line: UInt = #line) {
        let list = anyElement(A11yUI.Audit.root)
        let scoped = list.waitForExistence(timeout: 10)
        let prefix = NSPredicate(format: "label CONTAINS %@", company)
        var queries = [buttons, staticTexts]
        if scoped { queries = [list.buttons, list.cells, list.staticTexts] + queries }
        for query in queries {
            let row = query.matching(prefix).firstMatch
            if row.waitForExistence(timeout: 4) {
                tapInContent(row, file: file, line: line)
                return
            }
        }
        XCTFail(
            "no invoice in the audit list mentions “\(company)”.\n\(identifiedElements())",
            file: file, line: line
        )
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
        revealAndTap(anyElement(A11yUI.AddRental.companyRow))
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

        // Revealed, not merely waited for: the rate lives below the fold on this form and the
        // row does not exist until the form scrolls to it.
        revealAndTap(textFields[A11yUI.AddRental.dailyRate])
        typeText(dailyRate)
        dismissKeyboard()
    }
}
