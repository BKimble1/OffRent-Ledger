import Foundation

enum ReminderKind: String, CaseIterable, Codable, Sendable {
    case rateRollover
    case confirmationOutstanding
    case awaitingPickup
    case invoiceReview
    case disputeWindowClosing

    var displayName: String {
        switch self {
        case .rateRollover: "Rate change coming up"
        case .confirmationOutstanding: "Vendor confirmation not recorded"
        case .awaitingPickup: "Equipment still awaiting pickup"
        case .invoiceReview: "Invoice waiting for review"
        case .disputeWindowClosing: "Invoice dispute window closing"
        }
    }

    var explanation: String {
        switch self {
        case .rateRollover:
            "Before your next user-confirmed rate change, so you can decide whether to keep the machine."
        case .confirmationOutstanding:
            "When you marked equipment done but have not recorded a vendor confirmation number yet."
        case .awaitingPickup:
            "When equipment has been off-rented but is still sitting on the jobsite."
        case .invoiceReview:
            "When a final invoice is attached and has not been reviewed."
        case .disputeWindowClosing:
            "Before the review window you entered for this vendor runs out."
        }
    }

    /// Free users get the two that make the product work at all. The rest are Pro.
    var requiresPro: Bool {
        switch self {
        case .rateRollover, .confirmationOutstanding: false
        case .awaitingPickup, .invoiceReview, .disputeWindowClosing: true
        }
    }
}

struct ReminderSettings: Codable, Sendable, Equatable {
    var enabledKinds: Set<ReminderKind>
    /// Hours before a rate change to fire. 0 means at the boundary.
    var rolloverLeadHours: Int
    /// Hours after `equipmentMarkedDone` before nagging about a missing confirmation.
    var confirmationNagAfterHours: Int
    /// Days after off-rent confirmation before asking whether the machine actually left.
    var awaitingPickupAfterDays: Int
    /// Days after an invoice is attached before reminding the user to review it.
    var invoiceReviewAfterDays: Int
    /// Default dispute window, overridable per agreement.
    var defaultDisputeWindowDays: Int
    /// Days before the window closes to fire.
    var disputeWindowLeadDays: Int
    /// Reminders are pinned to this hour of the day so none of them fires at 3am.
    var preferredHour: Int
    /// Start of the window in which nothing fires, as an hour of the day.
    var quietHoursStart: Int
    /// End of that window. Wraps past midnight when it is smaller than the start, which is the
    /// normal case: 21 to 7.
    var quietHoursEnd: Int
    /// Whether the quiet window is honoured at all.
    var quietHoursEnabled: Bool

    static let `default` = ReminderSettings(
        enabledKinds: [],
        rolloverLeadHours: 24,
        confirmationNagAfterHours: 4,
        awaitingPickupAfterDays: 2,
        invoiceReviewAfterDays: 2,
        defaultDisputeWindowDays: 15,
        disputeWindowLeadDays: 3,
        preferredHour: 8,
        quietHoursStart: 21,
        quietHoursEnd: 7,
        quietHoursEnabled: true
    )

    func isEnabled(_ kind: ReminderKind) -> Bool { enabledKinds.contains(kind) }

    /// True when `hour` falls inside the quiet window, including a window that wraps midnight.
    func isQuiet(hour: Int) -> Bool {
        guard quietHoursEnabled, quietHoursStart != quietHoursEnd else { return false }
        if quietHoursStart < quietHoursEnd {
            return hour >= quietHoursStart && hour < quietHoursEnd
        }
        // 21 to 7: quiet late in the evening or early in the morning.
        return hour >= quietHoursStart || hour < quietHoursEnd
    }

    // MARK: - Codable

    // Written by hand so that settings saved by an earlier build still decode. Adding a stored
    // property to a synthesised `Codable` makes every previously saved value fail to decode,
    // which here would silently reset somebody's reminders to none — the exact failure that is
    // invisible until a reminder does not arrive.
    private enum CodingKeys: String, CodingKey {
        case enabledKinds, rolloverLeadHours, confirmationNagAfterHours, awaitingPickupAfterDays
        case invoiceReviewAfterDays, defaultDisputeWindowDays, disputeWindowLeadDays, preferredHour
        case quietHoursStart, quietHoursEnd, quietHoursEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = ReminderSettings.default
        func value<T: Decodable>(_ key: CodingKeys, _ backup: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) .flatMap { $0 } ?? backup
        }
        enabledKinds = value(.enabledKinds, fallback.enabledKinds)
        rolloverLeadHours = value(.rolloverLeadHours, fallback.rolloverLeadHours)
        confirmationNagAfterHours = value(.confirmationNagAfterHours, fallback.confirmationNagAfterHours)
        awaitingPickupAfterDays = value(.awaitingPickupAfterDays, fallback.awaitingPickupAfterDays)
        invoiceReviewAfterDays = value(.invoiceReviewAfterDays, fallback.invoiceReviewAfterDays)
        defaultDisputeWindowDays = value(.defaultDisputeWindowDays, fallback.defaultDisputeWindowDays)
        disputeWindowLeadDays = value(.disputeWindowLeadDays, fallback.disputeWindowLeadDays)
        preferredHour = value(.preferredHour, fallback.preferredHour)
        quietHoursStart = value(.quietHoursStart, fallback.quietHoursStart)
        quietHoursEnd = value(.quietHoursEnd, fallback.quietHoursEnd)
        quietHoursEnabled = value(.quietHoursEnabled, fallback.quietHoursEnabled)
    }

    init(
        enabledKinds: Set<ReminderKind>,
        rolloverLeadHours: Int,
        confirmationNagAfterHours: Int,
        awaitingPickupAfterDays: Int,
        invoiceReviewAfterDays: Int,
        defaultDisputeWindowDays: Int,
        disputeWindowLeadDays: Int,
        preferredHour: Int,
        quietHoursStart: Int = ReminderSettings.defaultQuietHoursStart,
        quietHoursEnd: Int = ReminderSettings.defaultQuietHoursEnd,
        quietHoursEnabled: Bool = true
    ) {
        self.enabledKinds = enabledKinds
        self.rolloverLeadHours = rolloverLeadHours
        self.confirmationNagAfterHours = confirmationNagAfterHours
        self.awaitingPickupAfterDays = awaitingPickupAfterDays
        self.invoiceReviewAfterDays = invoiceReviewAfterDays
        self.defaultDisputeWindowDays = defaultDisputeWindowDays
        self.disputeWindowLeadDays = disputeWindowLeadDays
        self.preferredHour = preferredHour
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
        self.quietHoursEnabled = quietHoursEnabled
    }

    static let defaultQuietHoursStart = 21
    static let defaultQuietHoursEnd = 7
}

/// One notification the app intends to have scheduled.
struct PlannedReminder: Sendable, Equatable, Identifiable {
    /// Stable and derived purely from (kind, item, boundary date). Rescheduling the same reminder
    /// produces the same identifier, so the OS replaces rather than duplicates it — which is what
    /// makes "edit a rental five times" not turn into five notifications.
    var id: String
    var kind: ReminderKind
    var itemID: UUID
    var fireDate: Date
    var title: String
    var body: String
    var deepLink: DeepLink

    static func identifier(kind: ReminderKind, itemID: UUID, fireDate: Date) -> String {
        "\(kind.rawValue)|\(itemID.uuidString)|\(Int(fireDate.timeIntervalSince1970))"
    }

    /// The same reminder at a different moment.
    ///
    /// The identifier has to move with the date or the OS would keep the old pending request and
    /// the reminder would fire at the time quiet hours were meant to avoid.
    func rescheduled(to newFireDate: Date) -> PlannedReminder {
        var moved = self
        moved.fireDate = newFireDate
        moved.id = PlannedReminder.identifier(kind: kind, itemID: itemID, fireDate: newFireDate)
        return moved
    }
}

/// What the planner needs to know about one item. Pure values, so the plan is a pure function.
struct ReminderContext: Sendable, Equatable {
    var itemID: UUID
    var equipmentName: String
    var status: RentalItemStatus
    var terms: RentalTerms
    var markedDoneAt: Date?
    var confirmationRecordedAt: Date?
    var pickupRecordedAt: Date?
    var invoiceAttachedAt: Date?
    var invoiceReviewed: Bool
    var disputeWindowDaysOverride: Int?

    init(
        itemID: UUID,
        equipmentName: String,
        status: RentalItemStatus,
        terms: RentalTerms,
        markedDoneAt: Date? = nil,
        confirmationRecordedAt: Date? = nil,
        pickupRecordedAt: Date? = nil,
        invoiceAttachedAt: Date? = nil,
        invoiceReviewed: Bool = false,
        disputeWindowDaysOverride: Int? = nil
    ) {
        self.itemID = itemID
        self.equipmentName = equipmentName
        self.status = status
        self.terms = terms
        self.markedDoneAt = markedDoneAt
        self.confirmationRecordedAt = confirmationRecordedAt
        self.pickupRecordedAt = pickupRecordedAt
        self.invoiceAttachedAt = invoiceAttachedAt
        self.invoiceReviewed = invoiceReviewed
        self.disputeWindowDaysOverride = disputeWindowDaysOverride
    }
}

/// Decides which local notifications *should* exist right now.
///
/// The planner produces a set; the scheduler diffs that set against what the OS actually holds
/// and adds or cancels the difference. Separating them is what makes "reschedule after every
/// edit" safe: the plan is recomputed from scratch each time and cannot accumulate.
///
/// Nothing here talks about remote notifications, because the app has no server and never
/// receives one.
enum ReminderPlanner {

    static func plan(
        contexts: [ReminderContext],
        settings: ReminderSettings,
        entitlement: EntitlementState,
        now: Date,
        calendar: Calendar
    ) -> [PlannedReminder] {
        var planned: [PlannedReminder] = []

        for context in contexts {
            // Closed items never nag. This is why resolving an item silently cleans up its
            // notifications rather than leaving a reminder for work that is finished.
            guard context.status.isOpen else { continue }

            for kind in ReminderKind.allCases {
                guard settings.isEnabled(kind) else { continue }
                if kind.requiresPro && !entitlement.isPro { continue }
                guard let reminder = reminder(
                    kind: kind, context: context, settings: settings, now: now, calendar: calendar
                ) else { continue }
                let moved = reminder.rescheduled(
                    to: respectingQuietHours(
                        reminder.fireDate, settings: settings, now: now, calendar: calendar
                    )
                )
                // A reminder for a moment that has already passed is noise on next launch.
                guard moved.fireDate > now else { continue }
                planned.append(moved)
            }
        }

        // Stable ordering keeps the diff against pending notifications deterministic.
        return planned.sorted { lhs, rhs in
            lhs.fireDate == rhs.fireDate ? lhs.id < rhs.id : lhs.fireDate < rhs.fireDate
        }
    }

    // MARK: - Per kind

    private static func reminder(
        kind: ReminderKind,
        context: ReminderContext,
        settings: ReminderSettings,
        now: Date,
        calendar: Calendar
    ) -> PlannedReminder? {

        switch kind {

        case .rateRollover:
            guard context.status.accruesRent else { return nil }
            guard let rollover = RentalRateEngine.nextRollover(
                terms: context.terms, asOf: now, calendar: calendar
            ) else { return nil }
            let fire = rollover.date.addingTimeInterval(-Double(settings.rolloverLeadHours) * 3600)
            let increment = rollover.expectedIncrement
            return make(
                kind: kind, context: context, fireDate: fire,
                title: "Rate change on \(context.equipmentName)",
                body: increment != nil
                    ? "Based on the terms you confirmed, the next period is expected to add about \(plainAmount(increment!)). Decide whether to keep the machine."
                    : "A rate change you confirmed is coming up. Decide whether to keep the machine.",
                link: .rentalItem(id: context.itemID)
            )

        case .confirmationOutstanding:
            guard context.status == .contactVendor, let markedDone = context.markedDoneAt else {
                return nil
            }
            let fire = markedDone.addingTimeInterval(Double(settings.confirmationNagAfterHours) * 3600)
            return make(
                kind: kind, context: context, fireDate: fire,
                title: "No confirmation recorded for \(context.equipmentName)",
                body: "You marked this done. \(SharedBranding.displayName) does not contact the rental company — call the vendor and record its confirmation number.",
                link: .recordConfirmation(itemID: context.itemID)
            )

        case .awaitingPickup:
            guard context.status == .awaitingPickup || context.status == .confirmationRecorded,
                  let confirmed = context.confirmationRecordedAt,
                  context.pickupRecordedAt == nil
            else { return nil }
            let fire = atPreferredHour(
                calendar.addingDaysPreservingTimeOfDay(settings.awaitingPickupAfterDays, to: confirmed),
                settings: settings, calendar: calendar
            )
            return make(
                kind: kind, context: context, fireDate: fire,
                title: "Still awaiting pickup: \(context.equipmentName)",
                body: "Has the rental company collected it? Record the pickup so your evidence is complete.",
                link: .rentalItem(id: context.itemID)
            )

        case .invoiceReview:
            guard let attached = context.invoiceAttachedAt, !context.invoiceReviewed else {
                return nil
            }
            let fire = atPreferredHour(
                calendar.addingDaysPreservingTimeOfDay(settings.invoiceReviewAfterDays, to: attached),
                settings: settings, calendar: calendar
            )
            return make(
                kind: kind, context: context, fireDate: fire,
                title: "Invoice waiting for review: \(context.equipmentName)",
                body: "Compare it against the terms you confirmed while the details are still fresh.",
                link: .rentalItem(id: context.itemID)
            )

        case .disputeWindowClosing:
            guard let attached = context.invoiceAttachedAt, !context.invoiceReviewed else {
                return nil
            }
            let window = context.disputeWindowDaysOverride ?? settings.defaultDisputeWindowDays
            guard window > 0 else { return nil }
            let closes = calendar.addingDaysPreservingTimeOfDay(window, to: attached)
            let fire = atPreferredHour(
                calendar.addingDaysPreservingTimeOfDay(-settings.disputeWindowLeadDays, to: closes),
                settings: settings, calendar: calendar
            )
            return make(
                kind: kind, context: context, fireDate: fire,
                title: "Review window closing: \(context.equipmentName)",
                body: "The review window you entered for this invoice ends soon. Check the vendor's terms for what applies.",
                link: .rentalItem(id: context.itemID)
            )
        }
    }

    private static func make(
        kind: ReminderKind,
        context: ReminderContext,
        fireDate: Date,
        title: String,
        body: String,
        link: DeepLink
    ) -> PlannedReminder {
        PlannedReminder(
            id: PlannedReminder.identifier(kind: kind, itemID: context.itemID, fireDate: fireDate),
            kind: kind,
            itemID: context.itemID,
            fireDate: fireDate,
            title: title,
            body: body,
            deepLink: link
        )
    }

    /// Moves a fire date to the user's preferred hour on the same calendar day.
    ///
    /// Applied to the day-scale reminders only. A rate-change reminder keeps its exact offset,
    /// because "24 hours before the rate changes" is the point of it.
    private static func atPreferredHour(
        _ date: Date, settings: ReminderSettings, calendar: Calendar
    ) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = min(23, max(0, settings.preferredHour))
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? date
    }

    /// Moves a fire time out of the user's quiet hours — earlier where possible, later otherwise.
    ///
    /// Earlier is the deliberate direction. Every reminder in this app warns about something with
    /// a deadline: a rate about to roll over, a review window about to close. A warning delivered
    /// after the thing it warned about is worse than one delivered a few hours early, so a
    /// reminder that lands inside the quiet window is pulled back to the moment the window opens.
    /// Only when that moment has already passed does it move forward to the window's end.
    static func respectingQuietHours(
        _ date: Date, settings: ReminderSettings, now: Date, calendar: Calendar
    ) -> Date {
        let hour = calendar.component(.hour, from: date)
        guard settings.isQuiet(hour: hour) else { return date }

        let wraps = settings.quietHoursStart > settings.quietHoursEnd
        let startedYesterday = wraps && hour < settings.quietHoursEnd
        let endsTomorrow = wraps && hour >= settings.quietHoursStart

        let startDay = startedYesterday
            ? calendar.addingDaysPreservingTimeOfDay(-1, to: date) : date
        let endDay = endsTomorrow
            ? calendar.addingDaysPreservingTimeOfDay(1, to: date) : date

        if let windowOpens = at(hour: settings.quietHoursStart, on: startDay, calendar: calendar),
           windowOpens > now {
            return windowOpens
        }
        return at(hour: settings.quietHoursEnd, on: endDay, calendar: calendar) ?? date
    }

    private static func at(hour: Int, on date: Date, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = min(23, max(0, hour))
        components.minute = 0
        components.second = 0
        return calendar.date(from: components)
    }

    /// A bare amount for notification text, where an attributed "estimate" qualifier cannot be
    /// rendered. The surrounding sentence always carries "Based on the terms you confirmed".
    private static func plainAmount(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        formatter.maximumFractionDigits = 2
        return formatter.string(from: MoneyMath.rounded(value) as NSDecimalNumber) ?? "\(value)"
    }
}
