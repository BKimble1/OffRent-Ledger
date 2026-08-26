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

    // MARK: - The App Store capture fixture

    #if DEBUG
    /// Writes the four machines, two companies and three jobsites the App Store screenshots are
    /// taken of, described by `AppStoreCaptureFixture`.
    ///
    /// **DEBUG only, and reached only from a launch that asked for a fresh store.** The launch
    /// argument that selects it (`-offrent-seed-appstore`) is read by `AppDependencies`, which
    /// returns no overrides at all in a Release build, and `verify_repository.py` fails the build
    /// if a reference to this function appears outside a `#if DEBUG` region.
    ///
    /// **Idempotent by construction.** It wipes before it writes, so running it twice leaves
    /// exactly the same store as running it once — which is what makes a capture session
    /// repeatable rather than cumulative.
    ///
    /// Every status here is assigned by `RentalWorkflowService`, through the same intents the
    /// user's own taps go through. There is no shortcut into `awaitingPickup`: the boom lift is
    /// activated, marked done and confirmed, exactly as somebody would have done it, so the
    /// timeline in the screenshot is a timeline of things that happened rather than a row of
    /// states that were assigned.
    @MainActor
    static func seedAppStore(context: ModelContext, clock: any Clock) {
        wipe(context: context)

        let workflow = RentalWorkflowService(context: context, clock: clock)
        var vendors: [UUID: Vendor] = [:]
        var sites: [UUID: JobSite] = [:]

        for company in AppStoreCaptureFixture.companies {
            let vendor = Vendor(
                id: company.id,
                name: company.name,
                branch: company.branch,
                phone: company.phone,
                email: company.email,
                standardNotes: company.standardNotes,
                contactName: company.contactName,
                address: company.address,
                createdAt: clock.now,
                modifiedAt: clock.now
            )
            context.insert(vendor)
            vendors[company.id] = vendor
        }

        for jobsite in AppStoreCaptureFixture.jobsites {
            let site = JobSite(
                id: jobsite.id,
                name: jobsite.name,
                projectIdentifier: jobsite.projectIdentifier,
                address: jobsite.address,
                placeName: jobsite.placeName,
                latitude: jobsite.latitude,
                longitude: jobsite.longitude,
                createdAt: clock.now,
                modifiedAt: clock.now
            )
            context.insert(site)
            sites[jobsite.id] = site
        }

        for machine in AppStoreCaptureFixture.machines {
            guard let vendor = vendors[machine.company.id], let site = sites[machine.jobsite.id] else {
                continue
            }
            // One agreement per machine, not one per company. `RootView` counts an invoice as
            // awaiting review for every item on the agreement it hangs off, so two machines
            // sharing a contract would report the one invoice twice — and the widget would say
            // "2 to review" beside an app that lists one.
            let agreement = RentalAgreement(
                id: machine.agreementID,
                agreementNumber: machine.agreementNumber,
                purchaseOrderNumber: machine.purchaseOrderNumber,
                startDate: machine.deliveredAt,
                scheduledEndDate: machine.scheduledEndAt,
                notes: nil,
                createdAt: clock.now,
                modifiedAt: clock.now,
                vendor: vendor,
                jobSite: site
            )
            context.insert(agreement)

            let item = RentalItem(
                id: machine.id,
                equipmentName: machine.equipmentName,
                equipmentClass: machine.equipmentClass,
                vendorEquipmentIdentifier: machine.vendorEquipmentIdentifier,
                serialNumber: machine.serialNumber,
                status: .draft,
                terms: machine.terms,
                meterUnit: machine.meterUnit,
                notes: nil,
                createdAt: machine.deliveredAt,
                modifiedAt: clock.now,
                agreement: agreement
            )
            context.insert(item)
            workflow.append(event: .created, to: item)
            workflow.apply(.activate, to: item)

            advance(item, to: machine, using: workflow, context: context)
            restamp(item, for: machine)
        }

        PersistentStore.saveDerived(context, describing: "the App Store capture fixtures")
    }

    /// Walks one machine from Active to wherever the fixture says it has got to.
    @MainActor
    private static func advance(
        _ item: RentalItem,
        to machine: AppStoreCaptureFixture.Machine,
        using workflow: RentalWorkflowService,
        context: ModelContext
    ) {
        guard machine.stage != .active, let confirmation = machine.confirmation else { return }

        workflow.apply(.markEquipmentDone, to: item)
        workflow.recordConfirmation(
            ConfirmationEvidence(
                confirmationNumber: confirmation.number,
                vendorRepresentative: confirmation.representative,
                contactMethod: confirmation.contactMethod,
                confirmedAt: confirmation.confirmedAt,
                notes: confirmation.note,
                // The one field the state machine will not move without. It is the user saying
                // they made the call, and a fixture that skipped it would be describing a
                // transition the app refuses.
                userAffirmedContact: true,
                meterReading: confirmation.meterReading,
                fuelLevel: confirmation.fuelLevel
            ),
            for: item
        )

        guard machine.stage == .invoiceReview, let pickup = machine.pickup,
              let invoice = machine.invoice
        else { return }

        workflow.recordPickup(
            PickupEvidence(
                pickedUpAt: pickup.pickedUpAt,
                observedBy: pickup.observedBy,
                finalMeterReading: pickup.finalMeterReading,
                finalFuelLevel: pickup.finalFuelLevel,
                notes: pickup.note
            ),
            for: item
        )

        let record = VendorInvoice(
            id: invoice.id,
            invoiceNumber: invoice.number,
            receivedDate: invoice.receivedAt,
            billedThroughDate: invoice.billedThroughAt,
            invoiceTotal: invoice.total,
            reviewStatus: .notReviewed,
            attachedAt: invoice.receivedAt,
            agreement: item.agreement,
            primaryItemID: item.id
        )
        context.insert(record)
        let line = InvoiceLine(
            category: .rentalSubtotal,
            detail: invoice.lineDetail,
            quantity: invoice.quantity,
            unitPrice: invoice.unitPrice,
            amount: invoice.rentalSubtotal,
            appearedInContract: true,
            invoice: record
        )
        context.insert(line)
        workflow.apply(.attachInvoice, to: item)
    }

    /// Back-dates the events the workflow stamped with "now", and gives each machine its own
    /// `modifiedAt`.
    ///
    /// Two different problems, one place.
    ///
    /// `RentalWorkflowService.append` timestamps an event with the clock, except for the two that
    /// carry a user-stated instant. That is correct for a person using the app — they mark a
    /// machine done at the moment they mark it done — and wrong for a fixture, where all six
    /// events would land on the same minute and the timeline would read "created, activated,
    /// marked done" *after* "picked up". Nothing about the workflow is bypassed: the events, the
    /// statuses and the transitions are all the service's; only the clock they were written at
    /// is moved to the one the fixture describes.
    ///
    /// The second problem is quieter. Every screen that lists rentals sorts by `modifiedAt`
    /// descending, and the service stamps all four with the same instant — so the order of the
    /// Rentals list, and of the map's search results, was whatever SwiftData felt like that run.
    /// A screenshot campaign cannot be built on that.
    @MainActor
    private static func restamp(_ item: RentalItem, for machine: AppStoreCaptureFixture.Machine) {
        let confirmedAt = machine.confirmation?.confirmedAt
        for event in item.sortedEvents {
            switch event.type {
            case .created:
                event.timestamp = machine.deliveredAt
            case .activated:
                // A minute after creation, not the same second. `sortedEvents` sorts by
                // timestamp and Swift's sort is not documented as stable, so two events sharing
                // an instant is a timeline whose order is a coin toss between runs.
                event.timestamp = machine.deliveredAt.addingTimeInterval(60)
            case .equipmentMarkedDone:
                // Forty minutes before the yard confirmed it: the user marked the machine done,
                // then rang, then wrote down what they were told.
                if let confirmedAt {
                    event.timestamp = confirmedAt.addingTimeInterval(-40 * 60)
                }
            case .invoiceAttached:
                if let received = machine.invoice?.receivedAt { event.timestamp = received }
            default:
                break
            }
        }
        item.modifiedAt = machine.lastTouchedAt
    }
    #endif
}
