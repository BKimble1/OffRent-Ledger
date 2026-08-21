import Foundation

/// How the vendor is billing this machine right now.
///
/// Only three bases exist in v1, and they are the three that are unambiguous across every rental
/// yard the app targets. "Monthly" is deliberately absent: vendors disagree about whether a month
/// is 28 days, 30 days, or the same date next month, and guessing wrong is a four-figure error.
/// A vendor billing calendar months is handled in manual rollover mode, where the user states the
/// next boundary and the app does not infer one.
enum BillingBasis: String, CaseIterable, Codable, Sendable {
    case daily
    case weekly
    case fourWeek

    /// The number of calendar days in one billing period.
    var dayCount: Int {
        switch self {
        case .daily: 1
        case .weekly: 7
        case .fourWeek: 28
        }
    }

    var displayName: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly (7 days)"
        case .fourWeek: "4-week (28 days)"
        }
    }

    var shortName: String {
        switch self {
        case .daily: "day"
        case .weekly: "week"
        case .fourWeek: "4 weeks"
        }
    }
}

/// The rates the user confirmed off the contract. All three are optional because a contract may
/// only quote one, and inventing the others is exactly the kind of helpfulness that produces a
/// number the user then cannot defend.
struct RateCard: Codable, Sendable, Equatable {
    var daily: Decimal?
    var weekly: Decimal?
    var fourWeek: Decimal?

    init(daily: Decimal? = nil, weekly: Decimal? = nil, fourWeek: Decimal? = nil) {
        self.daily = daily
        self.weekly = weekly
        self.fourWeek = fourWeek
    }

    func amount(for basis: BillingBasis) -> Decimal? {
        switch basis {
        case .daily: daily
        case .weekly: weekly
        case .fourWeek: fourWeek
        }
    }

    var isEmpty: Bool { daily == nil && weekly == nil && fourWeek == nil }

    /// Rates that are present but nonsensical. Zero counts: a $0.00 daily rate silently produces a
    /// $0.00 estimate, which looks like a working app showing good news.
    func issues() -> [RateValidationIssue] {
        var issues: [RateValidationIssue] = []
        for basis in BillingBasis.allCases {
            guard let amount = amount(for: basis) else { continue }
            if amount < .zero { issues.append(.negativeRate(basis)) }
            else if amount == .zero { issues.append(.zeroRate(basis)) }
        }
        return issues
    }
}

enum RateValidationIssue: Sendable, Equatable {
    case negativeRate(BillingBasis)
    case zeroRate(BillingBasis)
    case missingRateForBasis(BillingBasis)
    case rolloverBeforeDelivery
    case missingManualRollover
    case missingExpectedIncrement

    var message: String {
        switch self {
        case let .negativeRate(basis):
            "The \(basis.shortName) rate is negative."
        case let .zeroRate(basis):
            "The \(basis.shortName) rate is zero. Confirm that is really the rate."
        case let .missingRateForBasis(basis):
            "No \(basis.shortName) rate is confirmed, so rent cannot be estimated."
        case .rolloverBeforeDelivery:
            "The next rate change is before the delivery date."
        case .missingManualRollover:
            "Confirm the next rate change date."
        case .missingExpectedIncrement:
            "Confirm what the next rate change will add."
        }
    }

    /// Whether this issue stops an estimate from being produced at all, as opposed to being worth
    /// telling the user about while still estimating.
    var blocksEstimate: Bool {
        switch self {
        case .negativeRate, .missingRateForBasis: true
        case .zeroRate, .rolloverBeforeDelivery, .missingManualRollover, .missingExpectedIncrement:
            false
        }
    }
}

/// How the app decides when the next rate change happens.
enum RolloverMode: String, CaseIterable, Codable, Sendable {
    /// The default. The user states the next boundary; the app never infers one.
    case manual
    /// Opt-in. The app projects boundaries at a fixed interval from delivery, and every one of
    /// them is presented for confirmation before it is relied upon.
    case simpleSchedule

    var displayName: String {
        switch self {
        case .manual: "Manual (you confirm each change)"
        case .simpleSchedule: "Simple schedule"
        }
    }

    var explanation: String {
        switch self {
        case .manual:
            "\(SharedBranding.displayName) will not guess when your rate changes. You enter the next change date and what it adds."
        case .simpleSchedule:
            "\(SharedBranding.displayName) projects the next change at a fixed interval from delivery. You can confirm or override every one."
        }
    }
}

/// Everything the rate engine needs about one rental item. A pure value type, so an estimate can
/// be computed in a test, in a preview, in the widget snapshot builder, and in the PDF renderer
/// without any of them touching a database.
struct RentalTerms: Codable, Sendable, Equatable {
    var deliveryDate: Date
    var rateCard: RateCard
    var billingBasis: BillingBasis
    var rolloverMode: RolloverMode

    /// The user-confirmed next boundary. Authoritative in manual mode, and authoritative in
    /// simple-schedule mode too whenever `manualRolloverOverride` is set.
    var nextRolloverDate: Date?

    /// What the user expects the next boundary to add. In manual mode this is the only figure the
    /// app has, and it is never derived from the rate card behind the user's back.
    var expectedNextIncrement: Decimal?

    /// Optional interval for the boundary *after* next, in days.
    var subsequentIntervalDays: Int?

    var manualRolloverOverride: Bool

    /// Excess-hour, overtime and usage terms, kept verbatim for the user to read. v1 never
    /// computes against these — see `PROJECT_SOURCE_OF_TRUTH.md` §6.
    var includedUsageNotes: String?

    /// When the item stopped accruing, if it has. Estimates are computed to this instant rather
    /// than to "now" once the equipment is done, so a resolved rental's figure stops moving.
    var accrualStoppedAt: Date?

    init(
        deliveryDate: Date,
        rateCard: RateCard = RateCard(),
        billingBasis: BillingBasis = .daily,
        rolloverMode: RolloverMode = .manual,
        nextRolloverDate: Date? = nil,
        expectedNextIncrement: Decimal? = nil,
        subsequentIntervalDays: Int? = nil,
        manualRolloverOverride: Bool = false,
        includedUsageNotes: String? = nil,
        accrualStoppedAt: Date? = nil
    ) {
        self.deliveryDate = deliveryDate
        self.rateCard = rateCard
        self.billingBasis = billingBasis
        self.rolloverMode = rolloverMode
        self.nextRolloverDate = nextRolloverDate
        self.expectedNextIncrement = expectedNextIncrement
        self.subsequentIntervalDays = subsequentIntervalDays
        self.manualRolloverOverride = manualRolloverOverride
        self.includedUsageNotes = includedUsageNotes
        self.accrualStoppedAt = accrualStoppedAt
    }
}
