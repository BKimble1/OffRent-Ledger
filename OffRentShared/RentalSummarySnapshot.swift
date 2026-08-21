import Foundation

/// The only thing the widget is ever allowed to see.
///
/// A widget renders on the lock screen and in the Today view, where the viewer is not necessarily
/// the person who unlocked the phone. So this type carries counts, one aggregate figure and one
/// date — and it carries no vendor name, no jobsite, no equipment description, no agreement
/// number and no invoice amount. That is a structural guarantee rather than a rule someone has to
/// remember: there is no field here to put those things in.
///
/// The app writes it to App Group `UserDefaults`; the widget only reads. The widget never opens
/// the SwiftData store, so it cannot migrate it, lock it, or corrupt it from a background process.
struct RentalSummarySnapshot: Codable, Sendable, Equatable {

    /// Bumped alongside `SharedIdentifiers.snapshotDefaultsKey` whenever the shape changes.
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var generatedAt: Date

    /// Items still needing something from the user.
    var openItemCount: Int

    /// Items currently accruing an estimate.
    var accruingItemCount: Int

    /// Aggregate estimated rent running across every accruing item, as of `generatedAt`.
    /// Aggregate only — never per-item, because a single figure next to a single machine name
    /// would be exactly the disclosure this type exists to prevent.
    var estimatedRentRunning: Decimal

    var awaitingPickupCount: Int
    var invoicesAwaitingReviewCount: Int

    /// The soonest user-confirmed rollover across all items, if any.
    var nextRateChangeDate: Date?

    /// True when the user has never created a rental. Lets the widget show a real empty state
    /// rather than a row of zeroes that looks like a bug.
    var isEmpty: Bool { openItemCount == 0 && awaitingPickupCount == 0 && invoicesAwaitingReviewCount == 0 }

    init(
        schemaVersion: Int = RentalSummarySnapshot.currentSchemaVersion,
        generatedAt: Date,
        openItemCount: Int = 0,
        accruingItemCount: Int = 0,
        estimatedRentRunning: Decimal = .zero,
        awaitingPickupCount: Int = 0,
        invoicesAwaitingReviewCount: Int = 0,
        nextRateChangeDate: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.openItemCount = openItemCount
        self.accruingItemCount = accruingItemCount
        self.estimatedRentRunning = estimatedRentRunning
        self.awaitingPickupCount = awaitingPickupCount
        self.invoicesAwaitingReviewCount = invoicesAwaitingReviewCount
        self.nextRateChangeDate = nextRateChangeDate
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
            nextRateChangeDate: now.addingTimeInterval(60 * 60 * 36)
        )
    }

    static func empty(now: Date) -> RentalSummarySnapshot {
        RentalSummarySnapshot(generatedAt: now)
    }
}
