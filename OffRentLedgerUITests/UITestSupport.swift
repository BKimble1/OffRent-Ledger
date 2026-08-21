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
        ]
        app.launchArguments += seed.arguments
        app.launchArguments += entitlement.arguments
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

    /// Waits for an element and fails with the identifier rather than a bare timeout.
    @discardableResult
    func expect(
        _ element: XCUIElement,
        timeout: TimeInterval = 8,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        XCTAssertTrue(
            element.waitForExistence(timeout: timeout),
            "element did not appear: \(element.identifier)",
            file: file, line: line
        )
        return element
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
