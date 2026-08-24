import Foundation
import XCTest
@testable import OffRentDomain

/// Quiet hours, and the decision that a warning moves earlier rather than later.
final class QuietHoursTests: XCTestCase {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: iso)!
    }

    private func settings(start: Int = 21, end: Int = 7, on: Bool = true) -> ReminderSettings {
        var value = ReminderSettings.default
        value.quietHoursStart = start
        value.quietHoursEnd = end
        value.quietHoursEnabled = on
        return value
    }

    // MARK: - The window itself

    func testAWrappingWindowCoversTheEveningAndTheEarlyMorning() {
        let settings = self.settings(start: 21, end: 7)
        XCTAssertTrue(settings.isQuiet(hour: 22))
        XCTAssertTrue(settings.isQuiet(hour: 3))
        XCTAssertTrue(settings.isQuiet(hour: 21), "the window includes the hour it starts")
        XCTAssertFalse(settings.isQuiet(hour: 7), "the window excludes the hour it ends")
        XCTAssertFalse(settings.isQuiet(hour: 12))
    }

    func testANonWrappingWindowCoversOnlyTheHoursBetween() {
        let settings = self.settings(start: 9, end: 17)
        XCTAssertTrue(settings.isQuiet(hour: 12))
        XCTAssertFalse(settings.isQuiet(hour: 8))
        XCTAssertFalse(settings.isQuiet(hour: 20))
    }

    func testQuietHoursOffMeansNoHourIsQuiet() {
        let settings = self.settings(on: false)
        for hour in 0...23 { XCTAssertFalse(settings.isQuiet(hour: hour)) }
    }

    func testAZeroLengthWindowIsNotQuietAtAll() {
        let settings = self.settings(start: 9, end: 9)
        for hour in 0...23 { XCTAssertFalse(settings.isQuiet(hour: hour)) }
    }

    // MARK: - Moving a reminder

    func testAReminderInTheEveningMovesBackToTheStartOfTheWindow() {
        let moved = ReminderPlanner.respectingQuietHours(
            date("2026-05-09T23:30:00Z"),
            settings: settings(),
            now: date("2026-05-09T10:00:00Z"),
            calendar: calendar
        )
        XCTAssertEqual(moved, date("2026-05-09T21:00:00Z"))
    }

    /// The case the direction was chosen for: 3am on the 10th belongs to the window that opened
    /// at 9pm on the 9th, and the warning is more use before that than after it.
    func testAReminderInTheSmallHoursMovesBackToTheEveningBefore() {
        let moved = ReminderPlanner.respectingQuietHours(
            date("2026-05-10T03:00:00Z"),
            settings: settings(),
            now: date("2026-05-09T10:00:00Z"),
            calendar: calendar
        )
        XCTAssertEqual(moved, date("2026-05-09T21:00:00Z"))
    }

    /// When the window already opened, moving earlier would mean scheduling in the past. Then
    /// and only then does it move forward.
    func testAReminderMovesForwardWhenTheWindowHasAlreadyOpened() {
        let moved = ReminderPlanner.respectingQuietHours(
            date("2026-05-10T03:00:00Z"),
            settings: settings(),
            now: date("2026-05-09T23:00:00Z"),
            calendar: calendar
        )
        XCTAssertEqual(moved, date("2026-05-10T07:00:00Z"))
    }

    func testADaytimeReminderIsLeftExactlyWhereItIs() {
        let original = date("2026-05-09T14:20:00Z")
        XCTAssertEqual(
            ReminderPlanner.respectingQuietHours(
                original, settings: settings(), now: date("2026-05-09T10:00:00Z"), calendar: calendar
            ),
            original
        )
    }

    func testNothingMovesWhenQuietHoursAreOff() {
        let original = date("2026-05-09T23:30:00Z")
        XCTAssertEqual(
            ReminderPlanner.respectingQuietHours(
                original, settings: settings(on: false), now: date("2026-05-09T10:00:00Z"),
                calendar: calendar
            ),
            original
        )
    }

    func testMovingAReminderMovesItsIdentifierWithIt() {
        let itemID = UUID()
        let original = PlannedReminder(
            id: PlannedReminder.identifier(
                kind: .rateRollover, itemID: itemID, fireDate: date("2026-05-09T23:30:00Z")
            ),
            kind: .rateRollover,
            itemID: itemID,
            fireDate: date("2026-05-09T23:30:00Z"),
            title: "t", body: "b", deepLink: .rentalItem(id: itemID)
        )
        let moved = original.rescheduled(to: date("2026-05-09T21:00:00Z"))
        XCTAssertNotEqual(
            moved.id, original.id,
            "the identifier has to move or iOS keeps the pending request at the old time"
        )
        XCTAssertEqual(moved.fireDate, date("2026-05-09T21:00:00Z"))
        XCTAssertEqual(moved.kind, original.kind)
        XCTAssertEqual(moved.title, original.title)
    }

    // MARK: - Settings written by an earlier build

    /// The failure this guards is silent: a decode that throws would reset every reminder the
    /// user had switched on, and nobody finds out until a reminder does not arrive.
    func testSettingsSavedBeforeQuietHoursExistedStillDecode() throws {
        let legacy = """
            {
              "enabledKinds": ["rateRollover", "invoiceReview"],
              "rolloverLeadHours": 12,
              "confirmationNagAfterHours": 6,
              "awaitingPickupAfterDays": 3,
              "invoiceReviewAfterDays": 4,
              "defaultDisputeWindowDays": 20,
              "disputeWindowLeadDays": 5,
              "preferredHour": 9
            }
            """
        let decoded = try JSONDecoder().decode(
            ReminderSettings.self, from: Data(legacy.utf8)
        )
        XCTAssertEqual(decoded.enabledKinds, [.rateRollover, .invoiceReview])
        XCTAssertEqual(decoded.rolloverLeadHours, 12)
        XCTAssertEqual(decoded.preferredHour, 9)
        XCTAssertEqual(decoded.quietHoursStart, ReminderSettings.default.quietHoursStart)
        XCTAssertEqual(decoded.quietHoursEnd, ReminderSettings.default.quietHoursEnd)
        XCTAssertTrue(decoded.quietHoursEnabled)
    }

    func testSettingsRoundTripThroughJSON() throws {
        var original = ReminderSettings.default
        original.enabledKinds = [.awaitingPickup]
        original.quietHoursStart = 22
        original.quietHoursEnd = 6
        original.quietHoursEnabled = false
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(ReminderSettings.self, from: data), original)
    }
}
