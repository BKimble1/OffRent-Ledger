import Foundation
import XCTest

@testable import OffRentLedger

/// Where a link lands, and what happens to one that arrives at an awkward moment.
///
/// Until this release nothing read a tapped reminder at all, so none of this was reachable and
/// none of it was worth pinning. Now `NotificationRouter` hands the URL straight to `AppRouter`,
/// and the difference between "the reminder opens the rental it names" and "the reminder opens
/// the app" is entirely in here.
///
/// `DeepLinkTests` already round-trips every case through a URL, so nothing here repeats that.
/// These are about what the router does with a link once it has one — including a link that
/// arrives at the worst possible moment, which is the moment a notification is most likely to
/// arrive at.
@MainActor
final class DeepLinkRoutingTests: XCTestCase {

    // MARK: - Links land where they say

    func testAReminderAboutARentalOpensThatRental() {
        let router = AppRouter()
        let identifier = UUID()

        router.handle(.rentalItem(id: identifier))

        XCTAssertEqual(router.selectedTab, .rentals)
        XCTAssertEqual(router.rentalsPath.count, 1)
    }

    func testAReminderToConfirmOpensTheRentalAndTheSheet() {
        let router = AppRouter()
        let identifier = UUID()

        router.handle(.recordConfirmation(itemID: identifier))

        XCTAssertEqual(router.selectedTab, .rentals)
        XCTAssertEqual(router.rentalsPath.count, 1, "the sheet needs the item behind it")
        XCTAssertEqual(router.presentedSheet, .recordConfirmation(itemID: identifier))
    }

    func testSomethingThatIsNotOneOfOursIsRefused() throws {
        let router = AppRouter()
        let url = try XCTUnwrap(URL(string: "https://example.com/item/whatever"))

        XCTAssertFalse(router.handle(url: url), "a foreign URL must not be claimed")
        XCTAssertEqual(router.selectedTab, .today, "and must not move the user")
    }

    // MARK: - A link that arrives while a sheet is up

    func testASheetAskedForWhileAnotherIsUpWaitsRatherThanBeingLost() {
        let router = AppRouter()
        router.presentedSheet = .addRental

        router.handle(.recordConfirmation(itemID: UUID()))

        XCTAssertNil(
            router.presentedSheet,
            "the sheet that was up has to close first; `.sheet(item:)` will not swap one for another"
        )
    }

    func testTheWaitingSheetIsPresentedOnceTheFirstOneHasGone() {
        let router = AppRouter()
        let identifier = UUID()
        router.presentedSheet = .addRental

        router.handle(.recordConfirmation(itemID: identifier))
        router.sheetDidDismiss()

        XCTAssertEqual(
            router.presentedSheet, .recordConfirmation(itemID: identifier),
            "a reminder tapped mid-sheet still has to reach what it was about"
        )
    }

    func testAnOrdinaryDismissalDoesNotResurrectAnythingAfterwards() {
        let router = AppRouter()
        router.presentedSheet = .addRental

        router.presentedSheet = nil
        router.sheetDidDismiss()
        router.sheetDidDismiss()

        XCTAssertNil(router.presentedSheet, "nothing was queued, so nothing should appear")
    }

    func testAWaitingSheetIsDeliveredOnceAndNotAgain() {
        let router = AppRouter()
        router.presentedSheet = .addRental

        router.handle(.addRental)
        router.sheetDidDismiss()
        XCTAssertEqual(router.presentedSheet, .addRental)

        router.presentedSheet = nil
        router.sheetDidDismiss()
        XCTAssertNil(router.presentedSheet, "the queue holds one request, not a standing order")
    }

    func testALinkWithNoSheetShowingPresentsImmediately() {
        let router = AppRouter()

        router.handle(.addRental)

        XCTAssertEqual(
            router.presentedSheet, .addRental,
            "there was nothing to wait for, so waiting would be a dropped tap"
        )
    }
}
