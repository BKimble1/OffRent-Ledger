import Foundation
import Testing
import UserNotifications
@testable import OffRentLedger

/// The scheduler adapter's diffing behaviour, using the recording double.
///
/// This covers the *logic*, not delivery. Whether iOS shows a banner is a device gate and is
/// recorded as unverified in TEST_MATRIX.md.
///
/// NOT EXECUTED — no Xcode in the build environment.
struct NotificationSchedulerTests {

    private func plan(_ ids: [String]) -> [PlannedReminder] {
        ids.map {
            PlannedReminder(
                id: $0, kind: .rateRollover, itemID: UUID(),
                fireDate: Date(timeIntervalSince1970: 1_780_000_000),
                title: "t", body: "b", deepLink: .today
            )
        }
    }

    @Test func synchronisingAddsWhatIsMissingAndCancelsWhatIsNot() async {
        let scheduler = RecordingNotificationScheduler()

        let first = await scheduler.synchronise(to: plan(["a", "b"]))
        #expect(Set(first.added) == ["a", "b"])

        let second = await scheduler.synchronise(to: plan(["b", "c"]))
        #expect(Set(second.added) == ["c"])
        #expect(Set(second.cancelled) == ["a"])
        #expect(Set(second.unchanged) == ["b"])
    }

    @Test func reschedulingTheSamePlanIsANoOp() async {
        let scheduler = RecordingNotificationScheduler()
        _ = await scheduler.synchronise(to: plan(["a", "b"]))
        let again = await scheduler.synchronise(to: plan(["a", "b"]))
        #expect(again.added.isEmpty)
        #expect(again.cancelled.isEmpty)
        #expect(Set(again.unchanged) == ["a", "b"])
    }

    @Test func nothingIsScheduledWithoutAuthorisation() async {
        let scheduler = RecordingNotificationScheduler(status: .denied)
        let outcome = await scheduler.synchronise(to: plan(["a"]))
        #expect(outcome.added.isEmpty)
        #expect(await scheduler.pendingIdentifiers().isEmpty)
    }

    @Test func authorisationIsNeverRequestedBySynchronising() async {
        // Permission is asked for exactly once, from the reminder settings screen, after the user
        // turns something on. An app that prompts on launch gets denied on launch.
        let scheduler = RecordingNotificationScheduler(status: .notDetermined)
        _ = await scheduler.synchronise(to: plan(["a"]))
        #expect(scheduler.authorizationRequestCount == 0)
    }

    @Test func cancelAllEmptiesThePendingSet() async {
        let scheduler = RecordingNotificationScheduler()
        _ = await scheduler.synchronise(to: plan(["a", "b"]))
        await scheduler.cancelAll()
        #expect(await scheduler.pendingIdentifiers().isEmpty)
    }
}
