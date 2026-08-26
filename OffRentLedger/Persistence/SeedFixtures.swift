import Foundation
import SwiftData

/// Deterministic fixtures for previews and for the UI test suite.
///
/// Every identifier and date here is fixed, so a UI test can assert on an exact figure rather
/// than on "some number appears". They are only ever inserted into an in-memory store or into a
/// store the app was launched with `-offrent-reset-state`, and `AppDependencies` refuses to seed
/// at all in a Release build.
enum SeedFixtures {

    static let vendorID = UUID(uuidString: "A0000000-0000-4000-8000-000000000001")!
    static let jobSiteID = UUID(uuidString: "A0000000-0000-4000-8000-000000000002")!
    static let agreementID = UUID(uuidString: "A0000000-0000-4000-8000-000000000003")!
    static let skidSteerID = UUID(uuidString: "A0000000-0000-4000-8000-000000000004")!
    static let excavatorID = UUID(uuidString: "A0000000-0000-4000-8000-000000000005")!

    /// 4 May 2026, 07:00 America/Chicago — the delivery date used throughout the test suite and
    /// in the §19 financial walkthrough.
    static func deliveryDate(calendar: Calendar) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 4
        components.hour = 7
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 1_777_000_000)
    }

    /// Empties the store, so `-offrent-reset-state` means what its name says.
    ///
    /// It did not. The flag was only a *permission* to seed — nothing was ever deleted — and on
    /// the on-disk store that made every scenario depend on which one ran before it. The suite
    /// got away with it until `InvoiceAcceptanceUITests` started passing: that scenario drives
    /// the fixture rental all the way to Resolved and leaves it there, so the next class to ask
    /// for a fresh store opened the rental and found `Reopen` where `Mark as done` should have
    /// been. The failure named a screen the test had never touched.
    ///
    /// DEBUG only, like every other test hook, and reached only from a launch that asked for it.
    @MainActor
    static func wipe(context: ModelContext) {
        // Deleted in dependency order — items before the agreements they hang off — so a
        // nullify rule never has to reach a record that has already gone.
        for item in (try? context.fetch(StoreQueries.allItems())) ?? [] { context.delete(item) }
        for invoice in (try? context.fetch(StoreQueries.allInvoices())) ?? [] { context.delete(invoice) }
        for agreement in (try? context.fetch(StoreQueries.allAgreements())) ?? [] { context.delete(agreement) }
        for site in (try? context.fetch(StoreQueries.allJobSites())) ?? [] { context.delete(site) }
        for vendor in (try? context.fetch(StoreQueries.allVendors())) ?? [] { context.delete(vendor) }
        for asset in (try? context.fetch(StoreQueries.allAssets())) ?? [] { context.delete(asset) }
        PersistentStore.saveDerived(context, describing: "the wiped fixtures")
    }

    @MainActor
    @discardableResult
    static func seedWalkthrough(context: ModelContext, clock: any Clock) -> RentalItem {
        let vendor = Vendor(
            id: vendorID,
            name: "Cedar Ridge Equipment Rental",
            branch: "Marlin Falls",
            phone: "+19405550148",
            email: "rentals@example.invalid",
            link: "https://example.invalid/cedar-ridge",
            standardNotes: "Ask for Dana. Off-rent line is option 2.",
            createdAt: clock.now,
            modifiedAt: clock.now
        )
        let site = JobSite(
            id: jobSiteID,
            name: "Ridgeline Phase 2",
            projectIdentifier: "RL-2",
            address: "1400 Ridgeline Parkway",
            notes: nil,
            createdAt: clock.now,
            modifiedAt: clock.now
        )
        let delivery = deliveryDate(calendar: clock.calendar)
        let agreement = RentalAgreement(
            id: agreementID,
            agreementNumber: "CR-44821",
            startDate: delivery,
            scheduledEndDate: clock.calendar.addingDaysPreservingTimeOfDay(14, to: delivery),
            disputeWindowDaysOverride: 15,
            notes: nil,
            createdAt: clock.now,
            modifiedAt: clock.now,
            vendor: vendor,
            jobSite: site
        )
        context.insert(vendor)
        context.insert(site)
        context.insert(agreement)

        let workflow = RentalWorkflowService(context: context, clock: clock)
        let item = RentalItem(
            id: skidSteerID,
            equipmentName: "Skid Steer Loader",
            equipmentClass: "75HP closed cab",
            vendorEquipmentIdentifier: "SS-2214",
            serialNumber: "A9KT4417732",
            status: .draft,
            terms: RentalTerms(
                deliveryDate: delivery,
                rateCard: RateCard(
                    daily: MoneyMath.parse("285.00"),
                    weekly: MoneyMath.parse("985.00"),
                    fourWeek: MoneyMath.parse("2450.00")
                ),
                billingBasis: .daily,
                rolloverMode: .manual,
                nextRolloverDate: clock.calendar.addingDaysPreservingTimeOfDay(7, to: delivery),
                expectedNextIncrement: MoneyMath.parse("285.00"),
                includedUsageNotes: "8 hrs/day, 40 hrs/week included. Excess billed at 1/8 of day rate."
            ),
            meterUnit: .hours,
            notes: nil,
            createdAt: clock.now,
            modifiedAt: clock.now,
            agreement: agreement
        )
        context.insert(item)
        workflow.append(event: .created, to: item)
        workflow.apply(.activate, to: item)
        return item
    }

    /// One open item and nothing else — the state a free user hits the limit from.
    @MainActor
    static func seedFreeLimit(context: ModelContext, clock: any Clock) {
        seedWalkthrough(context: context, clock: clock)
    }

    static let attachmentID = UUID(uuidString: "A0000000-0000-4000-8000-000000000006")!

    /// The walkthrough rental with one attachment on it, so the attachment editor is reachable.
    ///
    /// The bytes are deliberately not written. A UI test cannot take a photograph, and filing a
    /// real image through the picker is not something XCUITest can drive — so the record exists
    /// and the file does not, which is exactly the state the editor's preview has to handle
    /// gracefully and the one place in the app where "the record and the bytes are separate
    /// things" can actually be exercised. Renaming, captioning and removing do not read the file
    /// at all, so they behave here exactly as they do against a real photograph.
    @MainActor
    static func seedAttachment(context: ModelContext, clock: any Clock) {
        let item = seedWalkthrough(context: context, clock: clock)
        let asset = EvidenceAsset(
            id: attachmentID,
            relativePath: "fixtures/delivery-condition.jpg",
            mediaType: .image,
            displayName: "Photo 1",
            capturedAt: deliveryDate(calendar: clock.calendar),
            caption: nil,
            item: item
        )
        context.insert(asset)
    }
}
