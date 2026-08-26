#if DEBUG
import Foundation

/// The records the App Store screenshots are taken of.
///
/// **DEBUG only, and the whole file is.** Nothing here compiles into a Release build, nothing
/// here can reach the store on its own — it is a description, not a writer — and
/// `SeedFixtures.seedAppStore` is the only thing that turns it into rows. `verify_repository.py`
/// fails the build if any reference to it appears outside a `#if DEBUG` region, so "cannot be
/// used in a release build" is checked rather than promised.
///
/// ## Why this exists at all
///
/// The walkthrough fixture ages. It carries a delivery date in the past and a live clock, so the
/// running-rent estimate climbs by the day rate every twenty-four hours forever: a screenshot
/// taken from it in a year's time reads `$32,490`, which is not a rental, it is a lawsuit. This
/// fixture is pinned to one instant — `fixedNowISO8601` — and every date in it is expressed
/// relative to that instant, so the same six screenshots come out the same on any machine, on
/// any day, in any year.
///
/// ## Why it lives in Domain
///
/// Because it is arithmetic, and arithmetic is testable without a simulator. The figures below
/// are not asserted by eye against a screenshot; `AppStoreCaptureFixtureTests` runs them through
/// `RentalRateEngine`, `SnapshotBuilder` and `InvoiceComparisonEngine` — the same engines the app
/// runs — and fails if the running total, the widget counts or the invoice difference drift from
/// what the gallery's headlines and the placement guide claim.
///
/// ## Every record here is invented
///
/// The companies, the people, the yards, the streets and the numbers are fictional. The phone
/// numbers are in the 555-01xx range reserved for fiction, the email domains are `.invalid`, and
/// the coordinates are real land — a screenshot of a map needs streets under the pins — with
/// street names that are not. No customer's address, project, contact or paperwork is used.
enum AppStoreCaptureFixture {

    // MARK: - The instant everything is frozen at

    /// Pass this to `-offrent-fixed-now`. 9 May 2026, 10:00 America/Chicago.
    ///
    /// A Saturday morning: two machines running, one off rent waiting to be collected, one
    /// invoice in. Late enough into each rental that the figures mean something, early enough
    /// that none of them is alarming — and the one rate change inside Today's 48-hour window
    /// falls on the Monday, which is when a yard would roll one.
    static let fixedNowISO8601 = "2026-05-09T15:00:00Z"

    static let timeZoneIdentifier = "America/Chicago"

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
        return calendar
    }

    /// The same instant `-offrent-fixed-now` produces, so a test and a capture agree.
    static var now: Date {
        ISO8601DateFormatter().date(from: fixedNowISO8601) ?? Date(timeIntervalSince1970: 1_778_425_200)
    }

    /// A local wall-clock instant in the fixture's own time zone.
    ///
    /// Wall clock rather than an offset from `now`, because every date in this fixture is a thing
    /// somebody would say out loud — "delivered Tuesday at seven" — and an offset in seconds is
    /// the form in which a daylight-saving boundary quietly moves a delivery to 06:00.
    static func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? now
    }

    /// Money and meter readings, always through `MoneyMath.parse`, which pins `en_US_POSIX`.
    /// `Decimal(string:)` without a locale reads "425.00" as 42500 on a device set to German.
    static func amount(_ text: String) -> Decimal { MoneyMath.parse(text) ?? .zero }

    // MARK: - Rental companies

    struct Company: Sendable, Equatable {
        var id: UUID
        var name: String
        var branch: String
        var contactName: String
        var phone: String
        var email: String
        var address: String
        var standardNotes: String
    }

    static let summit = Company(
        id: UUID(uuidString: "B0000000-0000-4000-8000-000000000101")!,
        name: "Summit Rental Co.",
        branch: "Bexley Yard",
        contactName: "Dana Whitfield",
        phone: "+19725550142",
        email: "yard@summitrental.example.invalid",
        address: "1180 Bexley Yard Road, Fairhaven, TX 76109",
        standardNotes: "Off-rent line is option 2. Ask for the yard, not the counter."
    )

    static let ridgeway = Company(
        id: UUID(uuidString: "B0000000-0000-4000-8000-000000000102")!,
        name: "Ridgeway Equipment",
        branch: "North Depot",
        contactName: "Marcus Ojeda",
        phone: "+19405550177",
        email: "dispatch@ridgeway.example.invalid",
        address: "704 North Depot Lane, Fairhaven, TX 76112",
        standardNotes: "Confirmation numbers are emailed the same day."
    )

    static var companies: [Company] { [summit, ridgeway] }

    // MARK: - Jobsites

    struct Jobsite: Sendable, Equatable {
        var id: UUID
        var name: String
        var projectIdentifier: String
        var address: String
        var placeName: String
        var latitude: Double
        var longitude: Double
    }

    /// Three sites inside about ten kilometres of each other, so one map region shows all three
    /// with streets underneath rather than three pins on an empty green field.
    static let ridgeline = Jobsite(
        id: UUID(uuidString: "B0000000-0000-4000-8000-000000000201")!,
        name: "Ridgeline Phase 2",
        projectIdentifier: "RL-2",
        address: "1400 Ridgeline Parkway",
        placeName: "Ridgeline Parkway",
        latitude: 32.9010,
        longitude: -97.0405
    )

    static let harperCreek = Jobsite(
        id: UUID(uuidString: "B0000000-0000-4000-8000-000000000202")!,
        name: "Harper Creek Crossing",
        projectIdentifier: "HC-7",
        address: "2250 Harper Creek Road",
        placeName: "Harper Creek Road",
        latitude: 32.8462,
        longitude: -96.9912
    )

    static let oldMill = Jobsite(
        id: UUID(uuidString: "B0000000-0000-4000-8000-000000000203")!,
        name: "Old Mill Industrial Park",
        projectIdentifier: "OM-3",
        address: "780 Old Mill Way",
        placeName: "Old Mill Way",
        latitude: 32.9585,
        longitude: -96.9331
    )

    static var jobsites: [Jobsite] { [ridgeline, harperCreek, oldMill] }

    // MARK: - Evidence

    /// What the rental company said when the user rang to take a machine off rent.
    struct Confirmation: Sendable, Equatable {
        var confirmedAt: Date
        var number: String
        var representative: String
        var contactMethod: VendorContactMethod
        var meterReading: Decimal
        var fuelLevel: FuelLevel
        var note: String
    }

    /// What the user recorded when the machine actually left.
    struct Pickup: Sendable, Equatable {
        var pickedUpAt: Date
        var observedBy: String
        var finalMeterReading: Decimal
        var finalFuelLevel: FuelLevel
        var note: String
    }

    /// The vendor invoice, and only ever one rental line on it.
    ///
    /// One line, deliberately. A delivery charge and an environmental fee would each raise a
    /// "review this charge" flag the app has no basis for an opinion about, and the invoice total
    /// would then differ from the rental subtotal — so the closing screenshot would carry five
    /// figures where its whole argument is three.
    struct Invoice: Sendable, Equatable {
        var id: UUID
        var number: String
        var receivedAt: Date
        var billedThroughAt: Date
        var lineDetail: String
        var quantity: Decimal
        var unitPrice: Decimal
        var rentalSubtotal: Decimal

        /// The invoice total equals the sum of its lines, so the only thing the review screen has
        /// to say is the one difference that matters.
        var total: Decimal { rentalSubtotal }
    }

    // MARK: - Machines

    /// Where a machine has got to. Named for the states the app's own workflow uses.
    enum Stage: Sendable, Equatable {
        /// On the jobsite, accruing.
        case active
        /// Off rent, confirmed, still on site.
        case awaitingPickup
        /// Picked up, invoice in, waiting to be checked.
        case invoiceReview

        var status: RentalItemStatus {
            switch self {
            case .active: .active
            case .awaitingPickup: .awaitingPickup
            case .invoiceReview: .invoiceReview
            }
        }
    }

    struct Machine: Sendable {
        var id: UUID
        var agreementID: UUID
        var company: Company
        var jobsite: Jobsite
        var equipmentName: String
        var equipmentClass: String
        var vendorEquipmentIdentifier: String
        var serialNumber: String
        var agreementNumber: String
        var purchaseOrderNumber: String
        var deliveredAt: Date
        var scheduledEndAt: Date
        var dailyRate: Decimal
        var weeklyRate: Decimal
        var fourWeekRate: Decimal
        var nextRolloverAt: Date
        var includedUsageNotes: String
        var meterUnit: MeterUnit
        var stage: Stage
        /// When this machine's record was last touched.
        ///
        /// Given explicitly, and distinct for every machine, because every screen that lists
        /// rentals sorts by it. The workflow service stamps all four with the same instant, and
        /// four equal sort keys means SwiftData returns them in whatever order it likes — so the
        /// Rentals list, the map's search results and the order of Today's sections would differ
        /// between two runs of the same capture script.
        var lastTouchedAt: Date
        var confirmation: Confirmation?
        var pickup: Pickup?
        var invoice: Invoice?

        var status: RentalItemStatus { stage.status }

        /// The rate change the user confirmed adds another day at the same day rate. Stating it
        /// keeps `RentalRateEngine` out of `missingManualRollover`, and because the amount equals
        /// the rate card's own the estimate is arithmetically identical to a plain multiplication
        /// — a rollover that is honest about being an ordinary next day rather than a surprise.
        var expectedNextIncrement: Decimal { dailyRate }

        var terms: RentalTerms {
            RentalTerms(
                deliveryDate: deliveredAt,
                rateCard: RateCard(daily: dailyRate, weekly: weeklyRate, fourWeek: fourWeekRate),
                billingBasis: .daily,
                rolloverMode: .manual,
                nextRolloverDate: nextRolloverAt,
                expectedNextIncrement: expectedNextIncrement,
                includedUsageNotes: includedUsageNotes,
                // Accrual stops when the vendor confirmed off rent, not when the machine was
                // collected. That is the product's central claim about where the money stops,
                // and it is why the confirmed machines' figures below are frozen.
                accrualStoppedAt: confirmation?.confirmedAt
            )
        }
    }

    /// 6,000 lb mini excavator, five days in, still digging. The largest of the two running
    /// figures, and the one whose rate change lands inside Today's 48-hour window.
    static var miniExcavator: Machine {
        Machine(
            id: UUID(uuidString: "B0000000-0000-4000-8000-000000000301")!,
            agreementID: UUID(uuidString: "B0000000-0000-4000-8000-000000000401")!,
            company: summit,
            jobsite: ridgeline,
            equipmentName: "Mini Excavator",
            equipmentClass: "6,000 lb, rubber track",
            vendorEquipmentIdentifier: "EX-118",
            serialNumber: "5KX2290741",
            agreementNumber: "SR-58204",
            purchaseOrderNumber: "PO-4471",
            deliveredAt: at(2026, 5, 5, 7),
            scheduledEndAt: at(2026, 5, 19, 7),
            dailyRate: amount("425.00"),
            weeklyRate: amount("1450.00"),
            fourWeekRate: amount("3600.00"),
            nextRolloverAt: at(2026, 5, 11, 7),
            includedUsageNotes: "8 hrs/day, 40 hrs/week included. Excess billed at 1/8 of day rate.",
            meterUnit: .hours,
            stage: .active,
            lastTouchedAt: at(2026, 5, 9, 9, 55),
            confirmation: nil,
            pickup: nil,
            invoice: nil
        )
    }

    /// Towable light tower, a week in at a small day rate. The second running figure, and the
    /// reason the total is a number a contractor recognises rather than a round one.
    static var lightTower: Machine {
        Machine(
            id: UUID(uuidString: "B0000000-0000-4000-8000-000000000302")!,
            agreementID: UUID(uuidString: "B0000000-0000-4000-8000-000000000402")!,
            company: ridgeway,
            jobsite: harperCreek,
            equipmentName: "Towable Light Tower",
            equipmentClass: "4 × 1000W metal halide",
            vendorEquipmentIdentifier: "LT-044",
            serialNumber: "RW7714208",
            agreementNumber: "RE-11907",
            purchaseOrderNumber: "PO-4468",
            deliveredAt: at(2026, 5, 2, 6, 30),
            scheduledEndAt: at(2026, 5, 30, 6, 30),
            dailyRate: amount("95.00"),
            weeklyRate: amount("320.00"),
            fourWeekRate: amount("860.00"),
            nextRolloverAt: at(2026, 5, 16, 6, 30),
            includedUsageNotes: "Fuel on return. Generator hours logged at pickup.",
            meterUnit: .hours,
            stage: .active,
            lastTouchedAt: at(2026, 5, 9, 9, 40),
            confirmation: nil,
            pickup: nil,
            invoice: nil
        )
    }

    /// 45 ft articulating boom lift, off rent since 7 May and still standing on site. The
    /// evidence frame's machine: confirmation number, who said it, meter, fuel and condition.
    static var boomLift: Machine {
        Machine(
            id: UUID(uuidString: "B0000000-0000-4000-8000-000000000303")!,
            agreementID: UUID(uuidString: "B0000000-0000-4000-8000-000000000403")!,
            company: ridgeway,
            jobsite: oldMill,
            equipmentName: "Articulating Boom Lift",
            equipmentClass: "45 ft, diesel, 4WD",
            vendorEquipmentIdentifier: "BL-204",
            serialNumber: "RW8830155",
            agreementNumber: "RE-11884",
            purchaseOrderNumber: "PO-4455",
            deliveredAt: at(2026, 5, 1, 7),
            scheduledEndAt: at(2026, 5, 15, 7),
            dailyRate: amount("340.00"),
            weeklyRate: amount("1150.00"),
            fourWeekRate: amount("2900.00"),
            nextRolloverAt: at(2026, 5, 8, 7),
            includedUsageNotes: "Operator training certificates held on site.",
            meterUnit: .hours,
            stage: .awaitingPickup,
            lastTouchedAt: at(2026, 5, 7, 11, 22),
            confirmation: Confirmation(
                confirmedAt: at(2026, 5, 7, 11, 20),
                number: "OR-7318",
                representative: "Marcus Ojeda",
                contactMethod: .phone,
                meterReading: amount("214.6"),
                fuelLevel: .threeQuarters,
                note: "Boom washed down, no damage. Left inside the north gate for collection."
            ),
            pickup: nil,
            invoice: nil
        )
    }

    /// Compact track loader, finished, collected, and invoiced for one day more than the
    /// confirmation says. Eight days expected at $285; nine days billed. $285 apart.
    static var trackLoader: Machine {
        Machine(
            id: UUID(uuidString: "B0000000-0000-4000-8000-000000000304")!,
            agreementID: UUID(uuidString: "B0000000-0000-4000-8000-000000000404")!,
            company: summit,
            jobsite: ridgeline,
            equipmentName: "Compact Track Loader",
            equipmentClass: "74 HP, closed cab",
            vendorEquipmentIdentifier: "CTL-247",
            serialNumber: "5KX1180633",
            agreementNumber: "SR-57991",
            purchaseOrderNumber: "PO-4402",
            deliveredAt: at(2026, 4, 22, 7),
            scheduledEndAt: at(2026, 5, 6, 7),
            dailyRate: amount("285.00"),
            weeklyRate: amount("985.00"),
            fourWeekRate: amount("2450.00"),
            nextRolloverAt: at(2026, 4, 30, 7),
            includedUsageNotes: "8 hrs/day, 40 hrs/week included. Excess billed at 1/8 of day rate.",
            meterUnit: .hours,
            stage: .invoiceReview,
            lastTouchedAt: at(2026, 5, 6, 8, 4),
            confirmation: Confirmation(
                confirmedAt: at(2026, 4, 29, 16),
                number: "OR-6642",
                representative: "Dana Whitfield",
                contactMethod: .phone,
                meterReading: amount("612.4"),
                fuelLevel: .full,
                note: "Off rent as of this afternoon. Tracks and cab checked, nothing noted."
            ),
            pickup: Pickup(
                pickedUpAt: at(2026, 5, 1, 9, 15),
                observedBy: "Site foreman",
                finalMeterReading: amount("612.4"),
                finalFuelLevel: .full,
                note: "Collected from the Ridgeline laydown area."
            ),
            invoice: Invoice(
                id: UUID(uuidString: "B0000000-0000-4000-8000-000000000501")!,
                number: "SUM-30918",
                receivedAt: at(2026, 5, 6, 8),
                billedThroughAt: at(2026, 4, 30, 16),
                lineDetail: "Compact track loader, daily",
                quantity: amount("9"),
                unitPrice: amount("285.00"),
                rentalSubtotal: amount("2565.00")
            )
        )
    }

    /// All four, oldest-touched first.
    ///
    /// The order here is only the order they are written in. What the Rentals list, the map's
    /// results and Today's sections actually show is decided by `lastTouchedAt`, because every
    /// one of those screens sorts by `modifiedAt` descending — so the list reads mini excavator,
    /// light tower, boom lift, track loader, which is this array reversed.
    static var machines: [Machine] { [trackLoader, boomLift, lightTower, miniExcavator] }

    // MARK: - What the screenshots must show

    /// Everything the gallery claims, in one place, computed by the app's own engines.
    ///
    /// The templates' headlines, the placement guide and `marketing/screenshots/README.md` all
    /// quote these figures. `AppStoreCaptureFixtureTests` asserts each one, so a fixture edit
    /// that changes a number fails there rather than in a screenshot somebody has already
    /// uploaded.
    struct Expectations: Sendable, Equatable {
        var estimatedRentRunning: Decimal
        var openItemCount: Int
        var accruingItemCount: Int
        var awaitingPickupCount: Int
        var invoicesAwaitingReviewCount: Int
        var nextRateChangeDate: Date?
        var invoiceExpected: Decimal
        var invoiceInvoiced: Decimal
        var invoiceDifference: Decimal
    }

    static var expectations: Expectations {
        Expectations(
            estimatedRentRunning: amount("2885.00"),
            openItemCount: 4,
            accruingItemCount: 2,
            awaitingPickupCount: 1,
            invoicesAwaitingReviewCount: 1,
            nextRateChangeDate: at(2026, 5, 11, 7),
            invoiceExpected: amount("2280.00"),
            invoiceInvoiced: amount("2565.00"),
            invoiceDifference: amount("285.00")
        )
    }

    /// The widget snapshot the Home Screen capture must render, built the way the app builds it.
    static func snapshot(asOf instant: Date = AppStoreCaptureFixture.now) -> RentalSummarySnapshot {
        SnapshotBuilder.build(
            items: machines.map {
                SnapshotItemInput(
                    status: $0.status,
                    terms: $0.terms,
                    hasInvoiceAwaitingReview: $0.invoice != nil
                )
            },
            now: instant,
            calendar: calendar
        )
    }

    /// The comparison the closing frame shows, built the way the invoice review screen builds it.
    static func invoiceComparison(asOf instant: Date = AppStoreCaptureFixture.now) -> InvoiceComparison? {
        let machine = trackLoader
        guard let invoice = machine.invoice else { return nil }
        return InvoiceComparisonEngine.compare(
            InvoiceComparisonInput(
                terms: machine.terms,
                confirmationDate: machine.confirmation?.confirmedAt,
                pickupDate: machine.pickup?.pickedUpAt,
                invoice: InvoiceValue(
                    id: invoice.id,
                    invoiceNumber: invoice.number,
                    receivedDate: invoice.receivedAt,
                    billedThroughDate: invoice.billedThroughAt,
                    lines: [
                        InvoiceLineValue(
                            category: .rentalSubtotal,
                            detail: invoice.lineDetail,
                            quantity: invoice.quantity,
                            unitPrice: invoice.unitPrice,
                            amount: invoice.rentalSubtotal,
                            appearedInContract: true
                        ),
                    ],
                    invoiceTotal: invoice.total,
                    reviewStatus: .notReviewed
                ),
                calendar: calendar,
                now: instant
            )
        )
    }
}
#endif
