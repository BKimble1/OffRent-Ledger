import Foundation
import SwiftData
import Testing
@testable import OffRentLedger

/// The workflow service: transitions, events, accrual, and the estimate cache.
///
/// Executed on the simulator by the `offrent-fast-verify` workflow. See TEST_MATRIX.md.
@MainActor
struct WorkflowServiceTests {

    private func setUp() throws -> (ModelContext, RentalItem, FixedClock, RentalWorkflowService) {
        let clock = FixedClock(2026, 5, 9, 10)
        let context = ModelContext(try ModelContainerFactory.make(inMemory: true))
        let item = SeedFixtures.seedWalkthrough(context: context, clock: clock)
        return (context, item, clock, RentalWorkflowService(context: context, clock: clock))
    }

    @Test func markingDoneStopsAccrualImmediately() throws {
        let (_, item, clock, workflow) = try setUp()
        #expect(item.accrualStoppedAt == nil)

        workflow.apply(.markEquipmentDone, to: item)

        #expect(item.status == .contactVendor)
        #expect(item.accrualStoppedAt == clock.now)
    }

    @Test func confirmationBackdatesAccrualToTheVendorsTime() throws {
        // If the yard confirms off-rent as of 9am and the user types it in at 4pm, the 9am figure
        // is the one that will be on the invoice.
        let (_, item, clock, workflow) = try setUp()
        workflow.apply(.markEquipmentDone, to: item)

        let earlier = clock.now.addingTimeInterval(-6 * 3600)
        workflow.recordConfirmation(
            ConfirmationEvidence(
                confirmationNumber: "OR-44921", confirmedAt: earlier, userAffirmedContact: true
            ),
            for: item
        )
        #expect(item.accrualStoppedAt == earlier)
    }

    @Test func recordingConfirmationLandsOnAwaitingPickup() throws {
        let (_, item, clock, workflow) = try setUp()
        workflow.apply(.markEquipmentDone, to: item)

        let result = workflow.recordConfirmation(
            ConfirmationEvidence(
                confirmationNumber: "OR-44921", confirmedAt: clock.now, userAffirmedContact: true
            ),
            for: item
        )
        guard case .success = result else { return #expect(Bool(false), "confirmation refused") }
        #expect(item.status == .awaitingPickup)
        #expect(item.sortedEvents.contains { $0.type == .vendorConfirmationRecorded })
    }

    @Test func unaffirmedConfirmationChangesNothingAtAll() throws {
        let (_, item, clock, workflow) = try setUp()
        workflow.apply(.markEquipmentDone, to: item)
        let eventCount = item.sortedEvents.count

        let result = workflow.recordConfirmation(
            ConfirmationEvidence(
                confirmationNumber: "OR-44921", confirmedAt: clock.now, userAffirmedContact: false
            ),
            for: item
        )
        guard case .failure = result else { return #expect(Bool(false), "must be refused") }
        #expect(item.status == .contactVendor)
        #expect(item.sortedEvents.count == eventCount, "a refused transition must write no event")
    }

    @Test func aContactAttemptDoesNotAdvanceTheWorkflow() throws {
        // Ringing the yard and getting voicemail leaves the item where it was. That is the honest
        // state, and it is what keeps the timeline an account rather than a summary.
        let (_, item, _, workflow) = try setUp()
        workflow.apply(.markEquipmentDone, to: item)

        workflow.recordContactAttempt(
            method: .phone, representative: nil, note: "No answer", for: item
        )
        #expect(item.status == .contactVendor)
        #expect(item.sortedEvents.contains { $0.type == .vendorContactAttempted })
    }

    @Test func reopeningIntoAnAccruingStateRestartsTheClock() throws {
        let (_, item, clock, workflow) = try setUp()
        workflow.apply(.markEquipmentDone, to: item)
        #expect(item.accrualStoppedAt != nil)

        workflow.apply(.reopen(to: .active, reason: "Crew needs it another day"), to: item)
        #expect(item.status == .active)
        #expect(item.accrualStoppedAt == nil, "a machine back on rent must accrue again")
    }

    @Test func theEstimateCacheMatchesTheEngine() throws {
        let (_, item, clock, workflow) = try setUp()
        workflow.refreshEstimate(for: item)

        let engine = RentalRateEngine.estimate(
            terms: item.terms, asOf: clock.now, calendar: clock.calendar
        )
        #expect(item.cachedEstimatedRunningCost == engine.estimatedTotal)
        #expect(item.cachedEstimateIsComplete == engine.isComplete)
    }

    @Test func anIncompleteEstimateCachesNilRatherThanZero() throws {
        let (_, item, _, workflow) = try setUp()
        item.dailyRate = nil
        workflow.refreshEstimate(for: item)
        #expect(item.cachedEstimatedRunningCost == nil)
        #expect(item.cachedEstimateIsComplete == false)
    }
}
