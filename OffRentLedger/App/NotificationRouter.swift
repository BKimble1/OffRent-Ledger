import Foundation
import OSLog
import UserNotifications

/// What happens when a reminder is tapped, and what happens when one fires with the app open.
///
/// Neither happened before this. `NotificationScheduler` has always written a deep link into each
/// reminder's `userInfo` — `offrent://item/<uuid>` and the rest — and nothing ever read it,
/// because no object was ever installed as the notification centre's delegate. So a reminder
/// saying "Skid Steer Loader is still on rent" opened the app on whatever screen it was last
/// left on, and the rental it named was however many taps away. The payload was built correctly
/// and thrown away.
///
/// The second half matters more for anyone evaluating the app. Without `willPresent`, iOS
/// suppresses a notification entirely while the app is in the foreground. Settings has a "Send a
/// test reminder" button, and the obvious way to try it is to tap it and watch — which showed
/// nothing at all, for a reason no part of the screen could explain.
///
/// Not `@MainActor`: `UNUserNotificationCenterDelegate` is called on an arbitrary queue.
/// `@unchecked Sendable` for the same reason `CoreLocationOneShotProvider` is — the one stored
/// reference is only ever touched inside the main-actor hop below.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {

    private static let logger = Logger(subsystem: "com.idlery.offrent", category: "notifications")

    private let router: AppRouter

    init(router: AppRouter) {
        self.router = router
        super.init()
    }

    /// Show it, even with the app open.
    ///
    /// `.list` as well as `.banner` so a reminder that arrives while somebody is looking at the
    /// app is still in the notification centre afterwards, rather than being a banner they had
    /// one chance to read.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    /// Go where the reminder points.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let raw = response.notification.request.content
            .userInfo[NotificationPayloadKey.deepLink] as? String
        let router = self.router

        Task { @MainActor in
            defer { completionHandler() }
            guard let raw, let url = URL(string: raw) else {
                // A reminder with no destination is not an error — the test reminder has none —
                // so the app simply opens where it was.
                return
            }
            if !router.handle(url: url) {
                Self.logger.error(
                    "A reminder carried a link this build cannot open: \(raw, privacy: .public)"
                )
            }
        }
    }
}
