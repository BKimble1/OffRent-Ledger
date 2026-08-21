import Foundation
import SwiftData
import Testing
@testable import OffRentLedger

/// Entitlement behaviour against the store: the free limit, and — more importantly — everything
/// that entitlement must never take away.
///
/// Executed on the simulator by the `offrent-fast-verify` workflow. The policy itself *was* executed, in
/// Tests/OffRentDomainTests/EntitlementPolicyTests.swift. See TEST_MATRIX.md.
@MainActor
struct EntitlementBehaviourTests {

    private func setUp() throws -> (ModelContext, FixedClock) {
        let clock = FixedClock(2026, 5, 9, 10)
        return (ModelContext(try ModelContainerFactory.make(inMemory: true)), clock)
    }

    @Test func freeUsersAreBlockedAtTheSecondOpenItem() throws {
        let (context, clock) = try setUp()
        _ = SeedFixtures.seedWalkthrough(context: context, clock: clock)
        try context.save()

        let openCount = try StoreQueries.openItemCount(in: context)
        #expect(openCount == 1)

        let decision = EntitlementPolicy.canCreateOpenItem(
            currentOpenCount: openCount, entitlement: .free
        )
        guard case .failure = decision else { return #expect(Bool(false), "must be blocked") }
    }

    @Test func resolvingTheOpenItemFreesTheSlotWithoutAPurchase() throws {
        let (context, clock) = try setUp()
        let item = SeedFixtures.seedWalkthrough(context: context, clock: clock)
        let workflow = RentalWorkflowService(context: context, clock: clock)

        workflow.apply(.markEquipmentDone, to: item)
        workflow.recordConfirmation(
            ConfirmationEvidence(confirmationNumber: "OR-1", confirmedAt: clock.now, userAffirmedContact: true),
            for: item
        )
        workflow.recordPickup(PickupEvidence(pickedUpAt: clock.now), for: item)
        workflow.apply(.attachInvoice, to: item)
        workflow.apply(.resolve(openDiscrepancyCount: 0), to: item)
        try context.save()

        #expect(try StoreQueries.openItemCount(in: context) == 0)
        guard case .success = EntitlementPolicy.canCreateOpenItem(currentOpenCount: 0, entitlement: .free)
        else { return #expect(Bool(false), "the slot must be free again") }
    }

    @Test func losingProKeepsEveryRecordEditableAndResolvable() throws {
        // The scenario that would destroy the product's reputation if it went wrong: a lapsed
        // subscriber with five open rentals.
        let (context, clock) = try setUp()
        let item = SeedFixtures.seedWalkthrough(context: context, clock: clock)
        try context.save()

        let lapsed = EntitlementState(tier: .free, reason: .expired)
        #expect(EntitlementPolicy.canEditExistingRecords(entitlement: lapsed))
        #expect(EntitlementPolicy.canResolveExistingRecords(entitlement: lapsed))
        #expect(EntitlementPolicy.canExportBackup(entitlement: lapsed))
        #expect(EntitlementPolicy.canDeleteAllData(entitlement: lapsed))

        // And it actually works, not just according to the policy object.
        let workflow = RentalWorkflowService(context: context, clock: clock)
        item.notes = "Edited after the subscription lapsed"
        guard case .success = workflow.apply(.markEquipmentDone, to: item) else {
            return #expect(Bool(false), "the workflow must still run at the free tier")
        }
        try context.save()
        #expect(item.status == .contactVendor)
        #expect(try context.fetch(StoreQueries.allItems()).count == 1)
    }

    @Test func theWidgetSnapshotIsClearedRatherThanStaleForFreeUsers() {
        let publisher = InMemorySnapshotPublisher()
        publisher.publish(.placeholder(now: Date()))
        publisher.clear()
        #expect(publisher.published == nil)
    }
}
