import Foundation
import XCTest
@testable import OffRentDomain

/// The walkthrough that replaced the one you could not finish.
///
/// The previous guide derived its step from a real rental's status, so it could only be
/// completed by actually creating a rental, ringing a rental company, recording a pickup and
/// accepting an invoice. On the day somebody installs the app they have none of those, and the
/// only exit was `Skip`. These assert the properties that fixes: it is a fixed sequence, it ends,
/// and finishing is a real end.
final class WalkthroughScriptTests: XCTestCase {

    func testThereAreEnoughPagesToBeUsefulAndFewEnoughToBeRead() {
        XCTAssertGreaterThanOrEqual(WalkthroughScript.count, 5)
        XCTAssertLessThanOrEqual(WalkthroughScript.count, 8)
    }

    func testEveryPageHasATitleABodyAndASymbol() {
        for page in WalkthroughScript.pages {
            XCTAssertFalse(page.title.isEmpty, "page \(page.id)")
            XCTAssertGreaterThan(page.body.count, 40, "page \(page.id)")
            XCTAssertFalse(page.symbol.isEmpty, "page \(page.id)")
        }
    }

    func testPageIdentifiersAreTheirIndexSoASequenceCannotDesync() {
        for (index, page) in WalkthroughScript.pages.enumerated() {
            XCTAssertEqual(page.id, index)
        }
    }

    func testTheSequenceHasAFirstAndALast() {
        XCTAssertTrue(WalkthroughScript.isFirst(0))
        XCTAssertFalse(WalkthroughScript.isFirst(1))
        XCTAssertTrue(WalkthroughScript.isLast(WalkthroughScript.count - 1))
        XCTAssertFalse(WalkthroughScript.isLast(0))
    }

    func testTheForwardButtonSaysFinishExactlyOnceAndOnTheLastPage() {
        var finishes = 0
        for index in 0..<WalkthroughScript.count {
            if WalkthroughScript.forwardTitle(at: index) == "Finish" {
                finishes += 1
                XCTAssertEqual(index, WalkthroughScript.count - 1)
            } else {
                XCTAssertEqual(WalkthroughScript.forwardTitle(at: index), "Next")
            }
        }
        XCTAssertEqual(finishes, 1)
    }

    func testAnIndexPastTheEndIsStillTreatedAsTheEndRatherThanCrashing() {
        XCTAssertNil(WalkthroughScript.page(at: WalkthroughScript.count))
        XCTAssertNil(WalkthroughScript.page(at: -1))
        XCTAssertTrue(WalkthroughScript.isLast(WalkthroughScript.count + 5))
    }

    func testEveryPageNamesSomewhereInTheAppOrDeliberatelyNamesNowhere() {
        for page in WalkthroughScript.pages {
            XCTAssertTrue(WalkthroughFocus.allCases.contains(page.focus), "page \(page.id)")
        }
    }

    func testTheTourCoversTheFourTabs() {
        let focused = Set(WalkthroughScript.pages.map(\.focus))
        for tab in [WalkthroughFocus.today, .rentals, .audit, .settings] {
            XCTAssertTrue(focused.contains(tab), "\(tab) is never pointed at")
        }
    }

    // MARK: - Re-presentation

    func testSomebodyWhoHasNeverSeenItIsShownIt() {
        XCTAssertTrue(WalkthroughScript.shouldPresent(seenVersion: nil))
    }

    func testSomebodyWhoHasSeenThisVersionIsNotShownItAgain() {
        XCTAssertFalse(WalkthroughScript.shouldPresent(seenVersion: WalkthroughScript.version))
    }

    func testAnOlderVersionIsShownTheNewOne() {
        XCTAssertTrue(WalkthroughScript.shouldPresent(seenVersion: WalkthroughScript.version - 1))
    }

    func testAStoreWrittenByANewerBuildDoesNotReplayTheTour() {
        XCTAssertFalse(WalkthroughScript.shouldPresent(seenVersion: WalkthroughScript.version + 1))
    }

    // MARK: - What it must never say

    func testNoPageClaimsTheAppContactsOrStopsAnything() {
        let banned = [
            "we will contact", "we contact", "guaranteed", "verified overcharge",
            "legal proof", "vendor notified", "rental successfully ended",
        ]
        for page in WalkthroughScript.pages {
            let text = (page.title + " " + page.body).lowercased()
            for phrase in banned {
                XCTAssertFalse(text.contains(phrase), "page \(page.id) says \(phrase)")
            }
        }
    }

    func testTheCallStepSaysExplicitlyThatTheAppDoesNotMakeTheCall() {
        let page = WalkthroughScript.pages.first { $0.title.contains("You make the call") }
        XCTAssertNotNil(page)
        XCTAssertTrue(page?.body.contains("never contacts the rental company") ?? false)
    }
}
