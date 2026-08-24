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
            XCTFail(
                """
                element did not appear within \(timeout)s.
                Query: \(element)
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
