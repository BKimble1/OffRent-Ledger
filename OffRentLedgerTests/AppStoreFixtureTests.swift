import Foundation
import SwiftData
import Testing
@testable import OffRentLedger

/// The App Store capture fixture, as it lands in an actual store.
///
/// `AppStoreCaptureFixtureTests` (SwiftPM) asserts the arithmetic — the running total, the widget
/// counts, the three invoice figures. This asserts the part that needs SwiftData: that seeding
/// produces those records, in those statuses, with those events, through the workflow service
/// rather than around it, and that running it twice leaves exactly one copy of everything.
///
/// Executed on the simulator by the Verify workflow. See TEST_MATRIX.md.
@MainActor
struct AppStoreFixtureTests {

    private typealias Fixture = AppStoreCaptureFixture

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainerFactory.make(inMemory: true))
    }

    /// The same clock the capture script passes as `-offrent-fixed-now`.
    private var clock: any Clock { FixedClock(now: Fixture.now) }

    private func seeded() throws -> ModelContext {
        let context = try makeContext()
        SeedFixtures.seedAppStore(context: context, clock: clock)
        return context
    }

    private func items(in context: ModelContext) throws -> [RentalItem] {
        try context.fetch(StoreQueries.allItems())
    }

    private func machine(
        _ identifier: String, in context: ModelContext
    ) throws -> RentalItem {
        let all = try items(in: context)
        return try #require(all.first { $0.vendorEquipmentIdentifier == identifier })
    }

    // MARK: - What gets written

    @Test func seedingWritesEveryRecordTheGalleryNeeds() throws {
        let context = try seeded()
        let rentals = try items(in: context)
        let vendors = try context.fetch(StoreQueries.allVendors())
        let sites = try context.fetch(StoreQueries.allJobSites())
        let agreements = try context.fetch(StoreQueries.allAgreements())
        let invoices = try context.fetch(StoreQueries.allInvoices())

        #expect(rentals.count == 4)
        #expect(vendors.count == 2)
        #expect(sites.count == 3)
        #expect(agreements.count == 4)
        #expect(invoices.count == 1)
    }

    @Test func everyMachineLandsInTheStatusTheFixtureDescribes() throws {
        let context = try seeded()
        for described in Fixture.machines {
            let item = try machine(described.vendorEquipmentIdentifier, in: context)
            #expect(
                item.status == described.status,
                "\(described.vendorEquipmentIdentifier) is \(item.status.rawValue), "
                + "expected \(described.status.rawValue)"
            )
        }
    }

    @Test func everyJobsiteHasACoordinateSoTheMapFrameHasSomethingToDraw() throws {
        let context = try seeded()
        for site in try context.fetch(StoreQueries.allJobSites()) {
            #expect(site.coordinate != nil, "\(site.name) has no coordinate")
        }
        for item in try items(in: context) as [RentalItem] {
            #expect(item.agreement?.jobSite?.coordinate != nil,
                    "\(item.equipmentName) cannot be placed on the map")
        }
    }

    @Test func eachMachineHasItsOwnAgreementSoTheInvoiceIsCountedOnce() throws {
        // `RootView.publishSnapshot` marks an item as having an invoice awaiting review when
        // *its agreement* carries one. Two machines on one contract would make the widget say
        // "2 to review" beside an app listing one.
        let context = try seeded()
        let agreementIDs = try items(in: context).compactMap { $0.agreement?.id }
        #expect(Set(agreementIDs).count == agreementIDs.count)
    }

    // MARK: - The evidence the proof frame is of

    @Test func theConfirmedMachineCarriesItsWholeProof() throws {
        let context = try seeded()
        let item = try machine("BL-204", in: context)
        let confirmation = try #require(
            item.sortedEvents.last { $0.type == .vendorConfirmationRecorded }
        )

        #expect(confirmation.confirmationNumber == "OR-7318")
        #expect(confirmation.vendorRepresentative == "Marcus Ojeda")
        #expect(confirmation.contactMethod == .phone)
        #expect(confirmation.meterReading == money("214.6"))
        #expect(confirmation.fuelLevel == .threeQuarters)
        #expect(confirmation.detail?.isEmpty == false)
        #expect(confirmation.timestamp == Fixture.boomLift.confirmation?.confirmedAt)
    }

    @Test func accrualStopsWhenTheVendorConfirmedNotWhenTheFixtureRan() throws {
        // The product's central claim. If the fixture let `markEquipmentDone` set the stop, the
        // proof screenshot would show a machine that went on accruing for two days after the
        // rental company agreed it was off rent.
        let context = try seeded()
        let item = try machine("BL-204", in: context)
        #expect(item.accrualStoppedAt == Fixture.boomLift.confirmation?.confirmedAt)
    }

    @Test func theTimelineReadsInTheOrderThingsHappened() throws {
        // The workflow service stamps every event it appends with the clock, which for a fixture
        // means six events on one minute — a timeline where "created" comes after "picked up".
        let context = try seeded()
        let item = try machine("CTL-247", in: context)
        let events = item.sortedEvents

        let types: [RentalEventType] = events.map(\.type)
        #expect(types == [
            .created, .activated, .equipmentMarkedDone, .vendorConfirmationRecorded,
            .pickupRecorded, .invoiceAttached,
        ])
        for (earlier, later) in zip(events, events.dropFirst()) {
            #expect(earlier.timestamp <= later.timestamp)
        }
        #expect(events.first?.timestamp == Fixture.trackLoader.deliveredAt)
    }

    // MARK: - The invoice the closing frame is of

    @Test func theInvoiceIsTheOneTheClosingFrameShows() throws {
        let context = try seeded()
        let invoices = try context.fetch(StoreQueries.allInvoices())
        let invoice = try #require(invoices.first)

        #expect(invoice.invoiceNumber == "SUM-30918")
        #expect(invoice.invoiceTotal == money("2565.00"))
        #expect(invoice.reviewStatus == .notReviewed)
        #expect(invoice.expectedRentalSubtotalOverride == nil)
        #expect((invoice.lines ?? []).count == 1)
        #expect((invoice.lines ?? []).first?.category == .rentalSubtotal)
        #expect((invoice.lines ?? []).first?.amount == money("2565.00"))
        #expect(invoice.primaryItemID == Fixture.trackLoader.id)
    }

    @Test func theInvoiceReviewScreenDerivesTheAdvertisedThreeFigures() throws {
        let context = try seeded()
        let item = try machine("CTL-247", in: context)
        let invoice = try #require(item.latestInvoice)
        let events = item.sortedEvents

        let comparison = InvoiceComparisonEngine.compare(
            InvoiceComparisonInput(
                terms: item.terms,
                confirmationDate: events.last { $0.type == .vendorConfirmationRecorded }?.timestamp,
                pickupDate: events.last { $0.type == .pickupRecorded }?.timestamp,
                invoice: invoice.value,
                expectedRentalSubtotalOverride: invoice.expectedRentalSubtotalOverride,
                calendar: clock.calendar,
                now: clock.now
            )
        )

        #expect(comparison.expectedRentalSubtotal == money("2280.00"))
        #expect(comparison.invoicedRentalSubtotal == money("2565.00"))
        #expect(comparison.possibleVariance == money("285.00"))
    }

    // MARK: - The widget

    @Test func theSnapshotTheWidgetWouldRenderMatchesTheStore() throws {
        let context = try seeded()
        var inputs: [SnapshotItemInput] = []
        for item in try items(in: context) as [RentalItem] {
            let invoices: [VendorInvoice] = item.agreement?.invoices ?? []
            var awaiting = false
            for invoice in invoices {
                let status: InvoiceReviewStatus = invoice.reviewStatus
                if status == .notReviewed || status == .inReview { awaiting = true }
            }
            inputs.append(
                SnapshotItemInput(
                    status: item.status, terms: item.terms, hasInvoiceAwaitingReview: awaiting
                )
            )
        }
        let snapshot = SnapshotBuilder.build(
            items: inputs, now: clock.now, calendar: clock.calendar
        )

        #expect(snapshot == Fixture.snapshot())
        #expect(snapshot.estimatedRentRunning == money("2885.00"))
        #expect(snapshot.openItemCount == 4)
        #expect(snapshot.awaitingPickupCount == 1)
        #expect(snapshot.invoicesAwaitingReviewCount == 1)
    }

    // MARK: - Repeatability

    @Test func seedingTwiceLeavesExactlyOneCopyOfEverything() throws {
        // A capture session is re-run whenever a screenshot comes out wrong. If the second run
        // doubled the store, the second set of screenshots would show eight machines and twice
        // the running rent.
        let context = try seeded()
        SeedFixtures.seedAppStore(context: context, clock: clock)
        let rentals = try items(in: context)
        let vendors = try context.fetch(StoreQueries.allVendors())
        let sites = try context.fetch(StoreQueries.allJobSites())
        let invoices = try context.fetch(StoreQueries.allInvoices())

        #expect(rentals.count == 4)
        #expect(vendors.count == 2)
        #expect(sites.count == 3)
        #expect(invoices.count == 1)
    }

    @Test func seedingIsDeterministicAcrossRuns() throws {
        let first = try seeded()
        let second = try seeded()

        func fingerprint(_ context: ModelContext) throws -> [String] {
            try items(in: context)
                .sorted { $0.id.uuidString < $1.id.uuidString }
                .map { item in
                    let estimate = item.cachedEstimatedRunningCost.map { "\($0)" } ?? "-"
                    return [
                        item.vendorEquipmentIdentifier ?? "-",
                        item.statusRaw,
                        estimate,
                        "\(item.modifiedAt.timeIntervalSince1970)",
                        item.sortedEvents.map(\.typeRaw).joined(separator: ">"),
                    ].joined(separator: "|")
                }
        }

        let before = try fingerprint(first)
        let after = try fingerprint(second)
        #expect(before == after)
    }

    @Test func wipingLeavesNothingBehind() throws {
        let context = try seeded()
        SeedFixtures.wipe(context: context)
        let rentals = try items(in: context)
        let invoices = try context.fetch(StoreQueries.allInvoices())
        let vendors = try context.fetch(StoreQueries.allVendors())

        #expect(rentals.isEmpty)
        #expect(invoices.isEmpty)
        #expect(vendors.isEmpty)
    }

    // MARK: - Nothing real, and nothing reachable in Release

    @Test func nothingInTheFixtureCouldBelongToAnybody() throws {
        let context = try seeded()
        for vendor in try context.fetch(StoreQueries.allVendors()) {
            #expect(vendor.email?.hasSuffix(".invalid") == true)
            #expect(vendor.phone?.contains("5550") == true)
        }
    }

    @Test func theLaunchArgumentIsIgnoredWhenNothingAskedForAFreshStore() throws {
        // `RootView.seedIfRequested` refuses to seed unless the launch also asked for an
        // in-memory store or a reset, so `-offrent-seed-appstore` on somebody's real store is
        // inert rather than destructive.
        #expect(LaunchArgument.seedAppStoreFixture == "-offrent-seed-appstore")
        let overrides = AppDependencies.testOverrides()
        #expect(overrides.seedAppStore == false, "this test bundle did not pass the flag")
    }
}
