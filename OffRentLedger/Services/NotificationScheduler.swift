import Foundation
import OSLog
import UserNotifications

/// Schedules local notifications. Local only — the app has no server and receives nothing.
protocol NotificationScheduling: Sendable {
    /// Current authorisation, without asking for it.
    func authorizationStatus() async -> UNAuthorizationStatus
    /// Asks. Called only after the user turns a reminder on.
    func requestAuthorization() async -> Bool
    /// Makes the OS's pending set match `planned` exactly: adds what is missing, cancels what is
    /// no longer wanted, leaves the rest alone.
    @discardableResult
    func synchronise(to planned: [PlannedReminder]) async -> ScheduleOutcome
    func cancelAll() async
    func pendingIdentifiers() async -> Set<String>
}

struct ScheduleOutcome: Sendable, Equatable {
    var added: [String]
    var cancelled: [String]
    var unchanged: [String]
    var failed: [String]

    static let empty = ScheduleOutcome(added: [], cancelled: [], unchanged: [], failed: [])
}

/// The `UNUserNotificationCenter` adapter.
///
/// It does no deciding. `ReminderPlanner` produces the set that should exist; this diffs that set
/// against what the OS holds and applies the difference. Keeping the decision out of here is what
/// makes "reschedule after every edit" safe and testable: the planner is a pure function with
/// tests, and this is a diff with no policy in it.
struct UserNotificationScheduler: NotificationScheduling {

    private static let logger = Logger(subsystem: "com.idlery.offrent", category: "notifications")

    private var center: UNUserNotificationCenter { .current() }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        do {
            // No `.badge`. A number on the icon is a nag the user did not ask for, and the app
            // has nothing that meaningfully counts down.
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            Self.logger.error("Authorisation request failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    func pendingIdentifiers() async -> Set<String> {
        Set(await center.pendingNotificationRequests().map(\.identifier))
    }

    @discardableResult
    func synchronise(to planned: [PlannedReminder]) async -> ScheduleOutcome {
        // Never asks for permission. If the user has not granted it, there is nothing to
        // schedule and no reason to interrupt them.
        guard await authorizationStatus() == .authorized else {
            await cancelAll()
            return .empty
        }

        let existing = await pendingIdentifiers()
        let wanted = Set(planned.map(\.id))

        let obsolete = existing.subtracting(wanted)
        if !obsolete.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(obsolete))
        }

        var added: [String] = []
        var failed: [String] = []
        let unchanged = Array(existing.intersection(wanted))

        for reminder in planned where !existing.contains(reminder.id) {
            do {
                try await center.add(request(for: reminder))
                added.append(reminder.id)
            } catch {
                Self.logger.error(
                    "Could not schedule \(reminder.kind.rawValue, privacy: .public): \(String(describing: error), privacy: .public)"
                )
                failed.append(reminder.id)
            }
        }

        Self.logger.info(
            "Reminders synchronised: +\(added.count, privacy: .public) -\(obsolete.count, privacy: .public) =\(unchanged.count, privacy: .public)"
        )
        return ScheduleOutcome(
            added: added, cancelled: Array(obsolete), unchanged: unchanged, failed: failed
        )
    }

    func cancelAll() async {
        center.removeAllPendingNotificationRequests()
    }

    private func request(for reminder: PlannedReminder) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.interruptionLevel = .active
        if let url = reminder.deepLink.url {
            content.userInfo = [NotificationPayloadKey.deepLink: url.absoluteString]
        }
        content.threadIdentifier = reminder.itemID.uuidString

        // Calendar components rather than a time interval. A device that changes time zone
        // between scheduling and firing should still fire at the intended wall-clock moment, and
        // a `UNTimeIntervalNotificationTrigger` would not.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute], from: reminder.fireDate
        )

        return UNNotificationRequest(
            identifier: reminder.id,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
    }
}

enum NotificationPayloadKey {
    static let deepLink = "offrent.deepLink"
}

/// Records what it was asked to do, and does nothing. Used by previews and the UI test suite.
final class RecordingNotificationScheduler: NotificationScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: Set<String> = []
    private(set) var status: UNAuthorizationStatus
    private(set) var authorizationRequestCount = 0
    private(set) var lastPlan: [PlannedReminder] = []

    init(status: UNAuthorizationStatus = .authorized) { self.status = status }

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    // Each `async` requirement below is a thin wrapper over a *synchronous* locked helper.
    //
    // `NSLock.lock()` is unavailable from an asynchronous context — an error in the Swift 6
    // language mode — precisely because taking a lock in an `async` function invites holding it
    // across a suspension point, which deadlocks the cooperative pool. Doing the locked work in
    // a synchronous function makes that structurally impossible: there is no `await` that could
    // be added between the `lock()` and the `defer`.

    func requestAuthorization() async -> Bool { recordAuthorizationRequest() }

    private func recordAuthorizationRequest() -> Bool {
        lock.lock(); defer { lock.unlock() }
        authorizationRequestCount += 1
        status = .authorized
        return true
    }

    func pendingIdentifiers() async -> Set<String> { currentPending() }

    private func currentPending() -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        return pending
    }

    @discardableResult
    func synchronise(to planned: [PlannedReminder]) async -> ScheduleOutcome {
        record(plan: planned)
    }

    private func record(plan planned: [PlannedReminder]) -> ScheduleOutcome {
        lock.lock(); defer { lock.unlock() }
        lastPlan = planned
        guard status == .authorized else { pending = []; return .empty }
        let wanted = Set(planned.map(\.id))
        let outcome = ScheduleOutcome(
            added: Array(wanted.subtracting(pending)),
            cancelled: Array(pending.subtracting(wanted)),
            unchanged: Array(pending.intersection(wanted)),
            failed: []
        )
        pending = wanted
        return outcome
    }

    func cancelAll() async { clearPending() }

    private func clearPending() {
        lock.lock(); defer { lock.unlock() }
        pending = []
    }
}
