import Foundation
import XCTest
@testable import OffRentDomain

/// The subscription rules. The tests that matter most here are the ones asserting what Pro does
/// *not* gate.
final class EntitlementPolicyTests: XCTestCase {

    func testFreePlanAllowsExactlyOneOpenItem() {
        XCTAssertEqual(EntitlementPolicy.freeOpenItemLimit, 1)
        guard case .success = EntitlementPolicy.canCreateOpenItem(currentOpenCount: 0, entitlement: .free)
        else { return XCTFail("the first open rental is free") }

        guard case let .failure(block) = EntitlementPolicy.canCreateOpenItem(
            currentOpenCount: 1, entitlement: .free
        ) else { return XCTFail("the second must be blocked") }
        XCTAssertEqual(block, .openItemLimitReached(limit: 1, current: 1))
    }

    func testFreeLimitMessageTellsTheUserBothWaysOut() {
        let message = EntitlementBlock.openItemLimitReached(limit: 1, current: 1).message
        XCTAssertTrue(message.contains("Resolve or archive"))
        XCTAssertTrue(message.contains("Pro"))
    }

    func testProAllowsUnlimitedOpenItems() {
        for count in [1, 2, 50, 5_000] {
            guard case .success = EntitlementPolicy.canCreateOpenItem(
                currentOpenCount: count, entitlement: .pro()
            ) else { return XCTFail("Pro must not be limited at \(count)") }
        }
    }

    func testResolvedAndArchivedItemsDoNotCountAgainstTheLimit() {
        let statuses: [RentalItemStatus] = [.resolved, .archived, .resolved, .active]
        XCTAssertEqual(EntitlementPolicy.openItemCount(statuses: statuses), 1)
    }

    func testEveryProFeatureIsOffForFreeAndOnForPro() {
        for feature in ProFeature.allCases {
            XCTAssertFalse(EntitlementPolicy.isAllowed(feature, entitlement: .free), "\(feature)")
            XCTAssertTrue(EntitlementPolicy.isAllowed(feature, entitlement: .pro()), "\(feature)")
        }
    }

    // MARK: - What entitlement never takes away

    func testExistingRecordsSurviveEveryEntitlementState() {
        let states: [EntitlementState] = [
            .free,
            EntitlementState(tier: .free, reason: .expired),
            EntitlementState(tier: .free, reason: .revoked),
            EntitlementState(tier: .free, reason: .inBillingRetry),
            .pro(),
            .pro(reason: .usingLastVerified),
        ]
        for state in states {
            XCTAssertTrue(EntitlementPolicy.canViewExistingRecords(entitlement: state), "\(state.reason)")
            XCTAssertTrue(EntitlementPolicy.canEditExistingRecords(entitlement: state), "\(state.reason)")
            XCTAssertTrue(EntitlementPolicy.canResolveExistingRecords(entitlement: state), "\(state.reason)")
            XCTAssertTrue(EntitlementPolicy.canDeleteExistingRecords(entitlement: state), "\(state.reason)")
            XCTAssertTrue(EntitlementPolicy.canDeleteAllData(entitlement: state), "\(state.reason)")
            XCTAssertTrue(EntitlementPolicy.canExportBackup(entitlement: state), "\(state.reason)")
            XCTAssertTrue(EntitlementPolicy.canExportSingleRentalCSV(entitlement: state), "\(state.reason)")
        }
    }

    func testAUserOverTheLimitAfterLosingProCanStillResolveTheirWayOut() {
        // The lapse scenario. Five open items, Pro gone. Creating a sixth is blocked; everything
        // needed to get back under the limit is not.
        let lapsed = EntitlementState(tier: .free, reason: .expired)
        guard case .failure = EntitlementPolicy.canCreateOpenItem(currentOpenCount: 5, entitlement: lapsed)
        else { return XCTFail("creation must be blocked over the limit") }

        XCTAssertTrue(EntitlementPolicy.canResolveExistingRecords(entitlement: lapsed))
        XCTAssertTrue(EntitlementPolicy.canEditExistingRecords(entitlement: lapsed))

        // Having resolved four, the next one is allowed again without any purchase.
        guard case .success = EntitlementPolicy.canCreateOpenItem(currentOpenCount: 0, entitlement: lapsed)
        else { return XCTFail("resolving must actually free the slot") }
    }

    func testOfflineProIsStillPro() {
        let offline = EntitlementState.pro(reason: .usingLastVerified, lastVerifiedAt: date(2026, 5, 1))
        XCTAssertTrue(offline.isPro)
        XCTAssertTrue(EntitlementPolicy.isAllowed(.invoiceAudit, entitlement: offline))
    }

    func testBillingRetryDoesNotSilentlyKeepProWhenTheTierSaysFree() {
        let retry = EntitlementState(tier: .free, reason: .inBillingRetry)
        XCTAssertFalse(EntitlementPolicy.isAllowed(.invoiceAudit, entitlement: retry))
        XCTAssertTrue(EntitlementPolicy.canEditExistingRecords(entitlement: retry))
    }

    /// The widget is not a Pro feature, and this is the test that says so.
    ///
    /// It was one. The gate contradicted the rule this whole type is built around — entitlement
    /// gates creating rentals, never seeing the ones already recorded — and in practice it meant
    /// a free user's Home Screen said "Open the app to start tracking a rental" over a phone with
    /// four machines on rent. If somebody adds `case widget` back, this fails.
    func testTheHomeScreenWidgetIsNotBehindTheSubscription() {
        XCTAssertFalse(
            ProFeature.allCases.contains { $0.rawValue.lowercased().contains("widget") },
            "the widget shows records the user already created, so it is not gated"
        )
    }
}
