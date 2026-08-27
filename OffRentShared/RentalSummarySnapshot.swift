import Foundation

/// The only thing the widget is ever allowed to see.
///
/// A widget renders on the lock screen as well as the Home Screen, and a lock screen is read by
/// whoever picks the phone up. So this type is split: the counts, the one aggregate figure and
/// the one date at the top are what the accessory families draw, and `rows` — which carries
/// machine names — is drawn only by the Home Screen families, behind Face ID.
///
/// What no family can draw, because there is nowhere to put it: a rental company, a jobsite, an
/// address, an agreement number, an invoice number, a confirmation number, a note, a serial.
/// `SnapshotBuilder` is the only thing that constructs this, and `SnapshotBuilderTests` asserts
/// the encoded JSON contains none of them.
///
/// The app writes it to App Group `UserDefaults`; the widget only reads. The widget never opens
/// the SwiftData store, so it cannot migrate it, lock it, or corrupt it from a background process.
struct RentalSummarySnapshot: Codable, Sendable, Equatable {

    /// One open rental, reduced to what a Home Screen widget may show.
    ///
    /// The machine name is the only free text anywhere in the snapshot, and it is here because a
    /// widget that says "3 open" without saying *which three* is a number, not a tool — which was
    /// exactly the complaint. Everything that identifies somebody other than the user stays out: no
    /// rental company, no jobsite, no address, no agreement number, no invoice or confirmation
    /// number. That remains structural rather than a rule to remember, because there is still no
    /// field here to put any of them in.
    ///
    /// `SummaryWidgetView` renders these only on the Home Screen families. The lock screen draws
    /// counts and the aggregate figure and nothing else — see the note on `RentalSummarySnapshot`.
    struct Row: Codable, Sendable, Equatable, Identifiable {

        /// Matches `RentalItem.id`, so a tap on the row opens that rental rather than the app's
        /// last tab. Not identifying on its own: a UUID names a row in the user's own store.
        var id: UUID

        /// The equipment, as the user typed it, trimmed to `machineNameLimit`.
        var machine: String

        var state: State

        /// This rental's own estimate, or `nil` when it is not accruing or the rate engine could not
        /// produce one. Deliberately optional rather than zero: a `$0` beside a machine that has been
        /// on rent for a week reads as "this one is free", which is the worst thing this app can say.
        var estimate: Decimal?

        /// Whole days since delivery, when the item is accruing.
        var daysOnRent: Int?

        /// The workflow states an open rental can be in, in the widget's own vocabulary.
        ///
        /// A separate enum from the app's `RentalItemStatus` because `OffRentShared` is compiled into
        /// the widget extension and the app's `Domain` folder is not. The labels mirror
        /// `RentalItemStatus.shortName` word for word so the widget and the app never describe the
        /// same rental differently.
        enum State: String, Codable, Sendable, CaseIterable {
            case draft
            case accruing
            case contactVendor
            case confirmationRecorded
            case awaitingPickup
            case pickedUp
            case awaitingInvoice
            case invoiceReview
            case needsFollowUp

            /// Short enough to sit beside a machine name and an amount in a widget row.
            var shortLabel: String {
                switch self {
                case .draft: "Draft"
                case .accruing: "Active"
                case .contactVendor: "To call"
                case .confirmationRecorded: "Confirmed"
                case .awaitingPickup: "Pickup due"
                case .pickedUp: "Picked up"
                case .awaitingInvoice: "Invoice due"
                case .invoiceReview: "Review"
                case .needsFollowUp: "Follow-up"
                }
            }

            /// Spoken by VoiceOver, where there is room for the whole phrase.
            var spokenLabel: String {
                switch self {
                case .draft: "Draft"
                case .accruing: "Active, rent running"
                case .contactVendor: "Contact the rental company"
                case .confirmationRecorded: "Vendor confirmation recorded"
                case .awaitingPickup: "Awaiting pickup"
                case .pickedUp: "Picked up"
                case .awaitingInvoice: "Awaiting invoice"
                case .invoiceReview: "Review this charge"
                case .needsFollowUp: "Needs follow-up"
                }
            }

            /// Sort order for the widget: the thing most worth doing something about goes first.
            ///
            /// Not the same as the workflow's own `order`, which runs oldest-stage-first. A widget
            /// has room for a handful of rows, so the ones it keeps should be the ones that cost
            /// money or need a phone call, not the ones furthest from being finished.
            var urgency: Int {
                switch self {
                case .invoiceReview: 0
                case .contactVendor: 1
                case .awaitingPickup: 2
                case .needsFollowUp: 3
                case .accruing: 4
                case .confirmationRecorded: 5
                case .awaitingInvoice: 6
                case .pickedUp: 7
                case .draft: 8
                }
            }

            /// True while the meter is still running, which is what the widget colours differently.
            var isAccruing: Bool { self == .accruing || self == .draft }
        }
    }

    /// Bumped alongside `SharedIdentifiers.snapshotDefaultsKey` whenever the shape changes.
    /// Version 2 added `rows`.
    static let currentSchemaVersion = 2

    /// The most rows the snapshot will carry.
    ///
    /// The largest family that draws them fits about eight, and an App Group blob that grows with
    /// the user's rental count is a blob that eventually stops being written. A contractor with
    /// thirty open rentals gets the eight most urgent plus the counts, which is what a glance is
    /// for.
    static let maxRows = 8

    /// The longest machine name the snapshot carries. Longer names are truncated here rather than
    /// only at render time, so one pathological name cannot bloat what every widget reload reads.
    static let machineNameLimit = 40

    var schemaVersion: Int
    var generatedAt: Date

    /// Items still needing something from the user.
    var openItemCount: Int

    /// Items currently accruing an estimate.
    var accruingItemCount: Int

    /// Aggregate estimated rent running across every accruing item, as of `generatedAt`.
    var estimatedRentRunning: Decimal

    var awaitingPickupCount: Int
    var invoicesAwaitingReviewCount: Int

    /// The soonest user-confirmed rollover across all items, if any.
    var nextRateChangeDate: Date?

    /// The open rentals, most urgent first, capped at `maxRows`.
    ///
    /// May hold fewer than `openItemCount` says. The count is the truth about how many there are;
    /// this is the truth about how many fit.
    var rows: [Row]

    /// True when the user has never created a rental. Lets the widget show a real empty state
    /// rather than a row of zeroes that looks like a bug.
    var isEmpty: Bool { openItemCount == 0 && awaitingPickupCount == 0 && invoicesAwaitingReviewCount == 0 }

    /// How many open rentals the widget could not fit, for a "+3 more" line.
    var hiddenRowCount: Int { max(0, openItemCount - rows.count) }

    init(
        schemaVersion: Int = RentalSummarySnapshot.currentSchemaVersion,
        generatedAt: Date,
        openItemCount: Int = 0,
        accruingItemCount: Int = 0,
        estimatedRentRunning: Decimal = .zero,
        awaitingPickupCount: Int = 0,
        invoicesAwaitingReviewCount: Int = 0,
        nextRateChangeDate: Date? = nil,
        rows: [Row] = []
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.openItemCount = openItemCount
        self.accruingItemCount = accruingItemCount
        self.estimatedRentRunning = estimatedRentRunning
        self.awaitingPickupCount = awaitingPickupCount
        self.invoicesAwaitingReviewCount = invoicesAwaitingReviewCount
        self.nextRateChangeDate = nextRateChangeDate
        self.rows = rows
    }

    /// Decoding tolerates a v1 blob missing `rows` rather than throwing. `SnapshotReader` rejects
    /// the wrong `schemaVersion` anyway, so this only ever matters if that check is relaxed — but
    /// a decode that throws where a default would do is a widget stuck on its placeholder.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        openItemCount = try container.decodeIfPresent(Int.self, forKey: .openItemCount) ?? 0
        accruingItemCount = try container.decodeIfPresent(Int.self, forKey: .accruingItemCount) ?? 0
        estimatedRentRunning =
            try container.decodeIfPresent(Decimal.self, forKey: .estimatedRentRunning) ?? .zero
        awaitingPickupCount = try container.decodeIfPresent(Int.self, forKey: .awaitingPickupCount) ?? 0
        invoicesAwaitingReviewCount =
            try container.decodeIfPresent(Int.self, forKey: .invoicesAwaitingReviewCount) ?? 0
        nextRateChangeDate = try container.decodeIfPresent(Date.self, forKey: .nextRateChangeDate)
        rows = try container.decodeIfPresent([Row].self, forKey: .rows) ?? []
    }

    static func placeholder(now: Date) -> RentalSummarySnapshot {
        RentalSummarySnapshot(
            generatedAt: now,
            openItemCount: 3,
            accruingItemCount: 2,
            estimatedRentRunning: Decimal(string: "1284.50", locale: Locale(identifier: "en_US_POSIX"))
                ?? .zero,
            awaitingPickupCount: 1,
            invoicesAwaitingReviewCount: 1,
            nextRateChangeDate: now.addingTimeInterval(60 * 60 * 36),
            // Generic machine names, because this is what the widget gallery shows every user
            // before they have installed it. Nothing here comes from anybody's store.
            rows: [
                Row(
                    id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1") ?? UUID(),
                    machine: "Skid Steer",
                    state: .accruing,
                    estimate: Decimal(string: "855.00", locale: Locale(identifier: "en_US_POSIX")),
                    daysOnRent: 3
                ),
                Row(
                    id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A2") ?? UUID(),
                    machine: "Mini Excavator",
                    state: .accruing,
                    estimate: Decimal(string: "429.50", locale: Locale(identifier: "en_US_POSIX")),
                    daysOnRent: 1
                ),
                Row(
                    id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A3") ?? UUID(),
                    machine: "Scissor Lift",
                    state: .awaitingPickup,
                    estimate: nil,
                    daysOnRent: nil
                ),
            ]
        )
    }

    static func empty(now: Date) -> RentalSummarySnapshot {
        RentalSummarySnapshot(generatedAt: now)
    }
}
