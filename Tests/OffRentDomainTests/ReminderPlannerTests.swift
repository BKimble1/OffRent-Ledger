import XCTest
@testable import OffRentDomain

/// Notification *scheduling logic*, tested independently of the operating system's delivery.
/// Whether iOS actually shows a banner is a device gate and is recorded as unverified.
final class ReminderPlannerTests: XCTestCase {

    private let now = date(2026, 5, 8, 10)
    private let itemID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    private func settings(_ kinds: Set<ReminderKind> = Set(ReminderKind.allCases)) -> ReminderSettings {
        var settings = ReminderSettings.default
        settings.enabledKinds = kinds
        return settings
    }

    private func context(
        status: RentalItemStatus = .active,
        terms: RentalTerms? = nil,
        markedDoneAt: Date? = nil,
        confirmationRecordedAt: Date? = nil,
        pickupRecordedAt: Date? = nil,
        invoiceAttachedAt: Date? = nil,
        invoiceReviewed: Bool = false,
        disputeWindowDaysOverride: Int? = nil
    ) -> ReminderContext {
        ReminderContext(
            itemID: itemID,
            equipmentName: "Skid steer SS-2214",
            status: status,
            terms: terms ?? .skidSteer(
                delivered: date(2026, 5, 4, 7),
                mode: .manual,
                nextRollover: date(2026, 5, 11, 7),
                expectedIncrement: "285.00"
            ),
            markedDoneAt: markedDoneAt,
            confirmationRecordedAt: confirmationRecordedAt,
            pickupRecordedAt: pickupRecordedAt,
            invoiceAttachedAt: invoiceAttachedAt,
            invoiceReviewed: invoiceReviewed,
            disputeWindowDaysOverride: disputeWindowDaysOverride
        )
    }

    private func plan(
        _ contexts: [ReminderContext],
        settings: ReminderSettings? = nil,
        entitlement: EntitlementState = .pro(),
        now: Date? = nil
    ) -> [PlannedReminder] {
        ReminderPlanner.plan(
            contexts: contexts,
            settings: settings ?? self.settings(),
            entitlement: entitlement,
            now: now ?? self.now,
            calendar: calendar()
        )
    }

    // MARK: - Nothing is scheduled unless it is asked for

    func testNoRemindersAreScheduledWhenNoneAreEnabled() {
        var off = ReminderSettings.default
        off.enabledKinds = []
        XCTAssertTrue(plan([context()], settings: off).isEmpty)
        XCTAssertTrue(
            ReminderSettings.default.enabledKinds.isEmpty,
            "reminders must be opt-in, so the app never asks for notification permission unprompted"
        )
    }

    func testClosedItemsNeverProduceReminders() {
        for status in [RentalItemStatus.resolved, .archived] {
            let planned = plan([
                context(
                    status: status,
                    markedDoneAt: date(2026, 5, 7),
                    confirmationRecordedAt: date(2026, 5, 7),
                    invoiceAttachedAt: date(2026, 5, 7)
                )
            ])
            XCTAssertTrue(planned.isEmpty, "\(status.displayName) still scheduled reminders")
        }
    }

    func testRemindersInThePastAreNotScheduled() {
        let planned = plan(
            [context(status: .contactVendor, markedDoneAt: date(2026, 5, 1, 8))],
            now: date(2026, 5, 8, 10)
        )
        XCTAssertFalse(planned.contains { $0.kind == .confirmationOutstanding })
    }

    // MARK: - Each kind

    func testRolloverReminderFiresAtTheConfiguredLead() {
        let planned = plan([context()]).filter { $0.kind == .rateRollover }
        XCTAssertEqual(planned.count, 1)
        // Rollover at 05-11 07:00, lead 24h.
        XCTAssertEqual(planned[0].fireDate, date(2026, 5, 10, 7))
        XCTAssertEqual(planned[0].deepLink, .rentalItem(id: itemID))
        XCTAssertTrue(planned[0].body.contains("Based on the terms you confirmed"))
        XCTAssertTrue(planned[0].body.contains("$285.00"))
    }

    func testRolloverReminderIsNotScheduledForItemsNoLongerAccruing() {
        for status in [RentalItemStatus.awaitingPickup, .pickedUp, .invoiceReview] {
            let planned = plan([context(status: status)]).filter { $0.kind == .rateRollover }
            XCTAssertTrue(planned.isEmpty, "\(status.displayName) is off-rent and must not warn about rate changes")
        }
    }

    func testRolloverReminderIsNotInventedWithoutAConfirmedDate() {
        let terms = RentalTerms.skidSteer(delivered: date(2026, 5, 4, 7), mode: .manual)
        let planned = plan([context(terms: terms)]).filter { $0.kind == .rateRollover }
        XCTAssertTrue(planned.isEmpty)
    }

    func testConfirmationReminderSaysTheAppDidNotContactTheVendor() {
        let planned = plan([
            context(status: .contactVendor, markedDoneAt: date(2026, 5, 8, 9))
        ]).filter { $0.kind == .confirmationOutstanding }

        XCTAssertEqual(planned.count, 1)
        XCTAssertEqual(planned[0].fireDate, date(2026, 5, 8, 13))   // +4h
        XCTAssertEqual(planned[0].deepLink, .recordConfirmation(itemID: itemID))
        XCTAssertTrue(
            planned[0].body.contains("does not contact the rental company"),
            "the one notification most likely to be misread must carry the disclosure"
        )
    }

    func testAwaitingPickupReminderFiresAtThePreferredHour() {
        let planned = plan([
            context(
                status: .awaitingPickup,
                confirmationRecordedAt: date(2026, 5, 8, 15),
                pickupRecordedAt: nil
            )
        ]).filter { $0.kind == .awaitingPickup }

        XCTAssertEqual(planned.count, 1)
        XCTAssertEqual(planned[0].fireDate, date(2026, 5, 10, 8))   // +2 days, pinned to 08:00
    }

    func testAwaitingPickupReminderStopsOncePickupIsRecorded() {
        let planned = plan([
            context(
                status: .awaitingPickup,
                confirmationRecordedAt: date(2026, 5, 8, 15),
                pickupRecordedAt: date(2026, 5, 9, 9)
            )
        ])
        XCTAssertFalse(planned.contains { $0.kind == .awaitingPickup })
    }

    func testInvoiceRemindersStopOnceTheInvoiceIsReviewed() {
        let unreviewed = plan([
            context(status: .invoiceReview, invoiceAttachedAt: date(2026, 5, 8, 9))
        ])
        XCTAssertTrue(unreviewed.contains { $0.kind == .invoiceReview })
        XCTAssertTrue(unreviewed.contains { $0.kind == .disputeWindowClosing })

        let reviewed = plan([
            context(
                status: .invoiceReview,
                invoiceAttachedAt: date(2026, 5, 8, 9),
                invoiceReviewed: true
            )
        ])
        XCTAssertFalse(reviewed.contains { $0.kind == .invoiceReview })
        XCTAssertFalse(reviewed.contains { $0.kind == .disputeWindowClosing })
    }

    func testDisputeWindowOverrideBeatsTheDefault() {
        let planned = plan([
            context(
                status: .invoiceReview,
                invoiceAttachedAt: date(2026, 5, 8, 9),
                disputeWindowDaysOverride: 7
            )
        ]).filter { $0.kind == .disputeWindowClosing }

        XCTAssertEqual(planned.count, 1)
        // attached 05-08 + 7 days = 05-15, minus 3 days lead = 05-12 at 08:00.
        XCTAssertEqual(planned[0].fireDate, date(2026, 5, 12, 8))
    }

    func testAZeroDayDisputeWindowSchedulesNothing() {
        let planned = plan([
            context(
                status: .invoiceReview,
                invoiceAttachedAt: date(2026, 5, 8, 9),
                disputeWindowDaysOverride: 0
            )
        ])
        XCTAssertFalse(planned.contains { $0.kind == .disputeWindowClosing })
    }

    // MARK: - Entitlement

    func testFreeUsersGetTheTwoRemindersThatMakeTheProductWork() {
        let planned = plan(
            [
                context(status: .contactVendor, markedDoneAt: date(2026, 5, 8, 9)),
                context(status: .invoiceReview, invoiceAttachedAt: date(2026, 5, 8, 9)),
            ],
            entitlement: .free
        )
        XCTAssertTrue(planned.contains { $0.kind == .confirmationOutstanding })
        XCTAssertFalse(planned.contains { $0.kind == .invoiceReview })
        XCTAssertFalse(planned.contains { $0.kind == .disputeWindowClosing })
    }

    // MARK: - Identity and duplication

    func testReschedulingTheSamePlanProducesIdenticalIdentifiers() {
        // This is what stops five edits becoming five notifications: the identifier is derived
        // from (kind, item, fire date), so the OS replaces rather than adds.
        let first = plan([context()])
        let second = plan([context()])
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertFalse(first.isEmpty)
    }

    func testChangingTheRolloverDateChangesTheIdentifier() {
        let original = plan([context()]).first { $0.kind == .rateRollover }
        var moved = context()
        moved.terms.nextRolloverDate = date(2026, 5, 14, 7)
        let updated = plan([moved]).first { $0.kind == .rateRollover }
        XCTAssertNotEqual(original?.id, updated?.id)
        XCTAssertEqual(updated?.fireDate, date(2026, 5, 13, 7))
    }

    func testIdentifiersAreUniqueAcrossAPlan() {
        let contexts = (0..<40).map { index in
            ReminderContext(
                itemID: UUID(),
                equipmentName: "Machine \(index)",
                status: .contactVendor,
                terms: .skidSteer(
                    delivered: date(2026, 5, 4, 7), mode: .manual,
                    nextRollover: date(2026, 5, 11, 7), expectedIncrement: "285.00"
                ),
                markedDoneAt: date(2026, 5, 8, 9)
            )
        }
        let planned = plan(contexts)
        XCTAssertEqual(Set(planned.map(\.id)).count, planned.count)
    }

    func testPlanIsSortedDeterministically() {
        let contexts = (0..<12).map { index in
            ReminderContext(
                itemID: UUID(),
                equipmentName: "Machine \(index)",
                status: .contactVendor,
                terms: .skidSteer(delivered: date(2026, 5, 4, 7)),
                markedDoneAt: date(2026, 5, 8, 9)
            )
        }
        let first = plan(contexts).map(\.id)
        let second = plan(contexts.reversed()).map(\.id)
        XCTAssertEqual(first, second, "plan order must not depend on input order")
    }

    // MARK: - Time zones

    func testDayScaleRemindersLandAtThePreferredHourAcrossASpringForward() {
        let planned = plan(
            [
                context(
                    status: .awaitingPickup,
                    confirmationRecordedAt: date(2026, 3, 6, 15),
                    pickupRecordedAt: nil
                )
            ],
            now: date(2026, 3, 6, 16)
        ).filter { $0.kind == .awaitingPickup }

        XCTAssertEqual(planned.count, 1)
        let hour = calendar().component(.hour, from: planned[0].fireDate)
        XCTAssertEqual(hour, 8, "a reminder must not drift to 7am because the clocks moved")
        XCTAssertEqual(calendar().component(.day, from: planned[0].fireDate), 8)
    }

    func testEveryPlannedReminderDeepLinksSomewhereReachable() {
        let planned = plan([
            context(status: .contactVendor, markedDoneAt: date(2026, 5, 8, 9)),
            context(status: .invoiceReview, invoiceAttachedAt: date(2026, 5, 8, 9)),
        ])
        XCTAssertFalse(planned.isEmpty)
        for reminder in planned {
            let url = try? XCTUnwrap(reminder.deepLink.url)
            XCTAssertEqual(DeepLink(url: url!), reminder.deepLink)
        }
    }

    func testNoReminderTextClaimsTheAppActedOrThatAnUpdateArrivedRemotely() {
        let planned = plan([
            context(status: .contactVendor, markedDoneAt: date(2026, 5, 8, 9)),
            context(status: .awaitingPickup, confirmationRecordedAt: date(2026, 5, 8, 9)),
            context(status: .invoiceReview, invoiceAttachedAt: date(2026, 5, 8, 9)),
        ])
        let banned = [
            "we notified", "vendor notified", "rental ended", "we contacted", "new update",
            "guaranteed", "overcharge",
        ]
        for reminder in planned {
            let text = (reminder.title + " " + reminder.body).lowercased()
            for phrase in banned {
                XCTAssertFalse(text.contains(phrase), "\(reminder.kind): \(phrase)")
            }
        }
    }
}

final class DeepLinkTests: XCTestCase {

    func testEveryCaseRoundTrips() {
        let identifier = UUID()
        let cases: [DeepLink] = [
            .today, .rentals, .audit, .addRental,
            .rentalItem(id: identifier),
            .recordConfirmation(itemID: identifier),
            .invoiceReview(invoiceID: identifier),
        ]
        for link in cases {
            guard let url = link.url else { return XCTFail("no URL for \(link)") }
            XCTAssertEqual(url.scheme, SharedIdentifiers.urlScheme)
            XCTAssertEqual(DeepLink(url: url), link, url.absoluteString)
        }
    }

    func testForeignSchemesAreRejected() {
        XCTAssertNil(DeepLink(url: URL(string: "https://example.com/today")!))
        XCTAssertNil(DeepLink(url: URL(string: "corecredit://today")!))
    }

    func testUnknownHostsAndMalformedIdentifiersAreRejected() {
        XCTAssertNil(DeepLink(url: URL(string: "offrent://nowhere")!))
        XCTAssertNil(DeepLink(url: URL(string: "offrent://item/not-a-uuid")!))
        XCTAssertNil(DeepLink(url: URL(string: "offrent://item")!))
        XCTAssertNil(DeepLink(url: URL(string: "offrent://confirm/")!))
    }

    func testHostMatchingIsCaseInsensitive() {
        XCTAssertEqual(DeepLink(url: URL(string: "OFFRENT://Today")!), .today)
    }
}
