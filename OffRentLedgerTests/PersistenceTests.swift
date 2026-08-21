import SwiftData
import Testing
@testable import OffRentLedger

/// SwiftData behaviour: relationships, cascades, and the round trip through the record types.
///
/// NOT EXECUTED — no Xcode in the build environment. See TEST_MATRIX.md.
@MainActor
struct PersistenceTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainerFactory.make(inMemory: true))
    }

    private func makeFixture(context: ModelContext, clock: any Clock) -> RentalItem {
        SeedFixtures.seedWalkthrough(context: context, clock: clock)
    }

    @Test func seedingProducesAnActiveItemWithItsRelationships() throws {
        let context = try makeContext()
        let clock = FixedClock(2026, 5, 9, 10)
        let item = makeFixture(context: context, clock: clock)

        #expect(item.status == .active)
        #expect(item.agreement?.vendor?.name == "Cedar Ridge Equipment Rental")
        #expect(item.agreement?.jobSite?.name == "Ridgeline Phase 2")
        #expect(item.sortedEvents.map(\.type) == [.created, .activated])
    }

    @Test func termsRoundTripThroughFlattenedColumns() throws {
        let context = try makeContext()
        let clock = FixedClock(2026, 5, 9, 10)
        let item = makeFixture(context: context, clock: clock)

        var terms = item.terms
        terms.billingBasis = .weekly
        terms.nextRolloverDate = clock.now
        terms.expectedNextIncrement = Decimal(string: "985.00")
        item.terms = terms

        #expect(item.billingBasisRaw == "weekly")
        #expect(item.terms.billingBasis == .weekly)
        #expect(item.terms.expectedNextIncrement == Decimal(string: "985.00"))
    }

    @Test func anUnknownStatusRawDegradesRatherThanCrashing() throws {
        // A store written by a newer build and opened by an older one must not take the app down.
        let context = try makeContext()
        let item = makeFixture(context: context, clock: FixedClock(2026, 5, 9, 10))
        item.statusRaw = "someFutureStatus"
        #expect(item.status == .draft)
    }

    @Test func deletingAnAgreementCascadesToItemsAndEvents() throws {
        let context = try makeContext()
        let clock = FixedClock(2026, 5, 9, 10)
        let item = makeFixture(context: context, clock: clock)
        let agreement = try #require(item.agreement)

        context.delete(agreement)
        try context.save()

        #expect(try context.fetch(StoreQueries.allItems()).isEmpty)
    }

    @Test func deletingAJobSiteKeepsItsRentals() throws {
        // Nullify, not cascade. A jobsite is a label; deleting it must not delete the money.
        let context = try makeContext()
        let clock = FixedClock(2026, 5, 9, 10)
        let item = makeFixture(context: context, clock: clock)
        let site = try #require(item.agreement?.jobSite)

        context.delete(site)
        try context.save()

        #expect(try context.fetch(StoreQueries.allItems()).count == 1)
        #expect(item.agreement?.jobSite == nil)
    }

    @Test func openItemsQueryExcludesResolvedAndArchived() throws {
        let context = try makeContext()
        let clock = FixedClock(2026, 5, 9, 10)
        let item = makeFixture(context: context, clock: clock)
        #expect(try context.fetchCount(StoreQueries.openItems()) == 1)

        let workflow = RentalWorkflowService(context: context, clock: clock)
        workflow.apply(.markEquipmentDone, to: item)
        workflow.recordConfirmation(
            ConfirmationEvidence(
                confirmationNumber: "OR-1", confirmedAt: clock.now, userAffirmedContact: true
            ),
            for: item
        )
        workflow.recordPickup(PickupEvidence(pickedUpAt: clock.now), for: item)
        workflow.apply(.attachInvoice, to: item)
        workflow.apply(.resolve(openDiscrepancyCount: 0), to: item)
        try context.save()

        #expect(try context.fetchCount(StoreQueries.openItems()) == 0)
    }

    @Test func recordsMapToArchiveRecordsAndBack() throws {
        let context = try makeContext()
        let clock = FixedClock(2026, 5, 9, 10)
        _ = makeFixture(context: context, clock: clock)
        try context.save()

        let service = ExportService(
            context: context,
            clock: clock,
            fileStore: AppFileStore(containerRoot: URL.temporaryDirectory)
        )
        let archive = try service.buildArchive()

        #expect(archive.vendors.count == 1)
        #expect(archive.items.count == 1)
        #expect(archive.formatVersion == BackupArchive.currentFormatVersion)

        let data = try BackupArchive.encoder().encode(archive)
        let decoded = try BackupArchive.decoder().decode(BackupArchive.self, from: data)
        #expect(decoded == archive)
    }

    @Test func importingIntoAStoreThatAlreadyHasTheRecordsAddsNothing() throws {
        let context = try makeContext()
        let clock = FixedClock(2026, 5, 9, 10)
        _ = makeFixture(context: context, clock: clock)
        try context.save()

        let service = ExportService(
            context: context, clock: clock,
            fileStore: AppFileStore(containerRoot: URL.temporaryDirectory)
        )
        let archive = try service.buildArchive()
        let preview = try service.apply(archive: archive)

        #expect(preview.willAdd.total == 0)
        #expect(try context.fetch(StoreQueries.allItems()).count == 1)
    }
}
