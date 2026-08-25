import Foundation
import OSLog
import WidgetKit

/// Publishes the widget's summary snapshot.
protocol SnapshotPublishing: Sendable {
    func publish(_ snapshot: RentalSummarySnapshot)
    /// No rentals to show, or no App Group. The widget shows its "nothing here yet" state.
    func clear()
    /// There *are* rentals, and the subscription that shows them has lapsed.
    ///
    /// Distinct from `clear()` on purpose. Before this, a free user's widget was cleared and
    /// therefore read exactly like an empty one: "No rentals yet" over a phone with four
    /// machines on rent. The widget is sold as a Pro feature, so its unpaid state has to say
    /// that rather than misreport the user's own data back to them.
    func withhold()
}

/// Writes the snapshot to the App Group and asks WidgetKit to reload.
///
/// The widget never opens the SwiftData store. It reads one small JSON blob that the app wrote,
/// which means a widget timeline refresh cannot migrate the store, cannot lock it against the
/// app, and cannot fail in a way the user would have to debug. It also means the widget is
/// structurally incapable of seeing anything `RentalSummarySnapshot` cannot carry — no vendor, no
/// jobsite, no equipment, no invoice amount.
struct AppGroupSnapshotPublisher: SnapshotPublishing {

    private static let logger = Logger(subsystem: "com.idlery.offrent", category: "widget")

    func publish(_ snapshot: RentalSummarySnapshot) {
        guard let defaults = UserDefaults(suiteName: SharedIdentifiers.appGroupIdentifier) else {
            // Missing App Group entitlement. The app works; the widget shows its placeholder.
            Self.logger.error("App Group unavailable — widget will not update")
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: SharedIdentifiers.snapshotDefaultsKey)
        defaults.removeObject(forKey: SharedIdentifiers.snapshotWithheldDefaultsKey)
        WidgetCenter.shared.reloadTimelines(ofKind: SharedIdentifiers.widgetKind)
    }

    func clear() {
        guard let defaults = UserDefaults(suiteName: SharedIdentifiers.appGroupIdentifier) else { return }
        defaults.removeObject(forKey: SharedIdentifiers.snapshotDefaultsKey)
        defaults.removeObject(forKey: SharedIdentifiers.snapshotWithheldDefaultsKey)
        WidgetCenter.shared.reloadTimelines(ofKind: SharedIdentifiers.widgetKind)
    }

    func withhold() {
        guard let defaults = UserDefaults(suiteName: SharedIdentifiers.appGroupIdentifier) else { return }
        // The snapshot goes, and only a flag stays. Nothing the entitlement was protecting is
        // left in the App Group for the widget to render by mistake.
        defaults.removeObject(forKey: SharedIdentifiers.snapshotDefaultsKey)
        defaults.set(true, forKey: SharedIdentifiers.snapshotWithheldDefaultsKey)
        WidgetCenter.shared.reloadTimelines(ofKind: SharedIdentifiers.widgetKind)
    }
}

/// Reads the snapshot. Compiled into the widget extension as well as the app.
enum SnapshotReader {
    static func read() -> RentalSummarySnapshot? {
        guard let defaults = UserDefaults(suiteName: SharedIdentifiers.appGroupIdentifier),
              let data = defaults.data(forKey: SharedIdentifiers.snapshotDefaultsKey)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(RentalSummarySnapshot.self, from: data) else {
            return nil
        }
        // A snapshot written by a newer app version is ignored rather than half-read.
        guard snapshot.schemaVersion == RentalSummarySnapshot.currentSchemaVersion else { return nil }
        return snapshot
    }
}

/// Keeps the snapshot in memory. Previews and tests.
final class InMemorySnapshotPublisher: SnapshotPublishing, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var published: RentalSummarySnapshot?
    private(set) var publishCount = 0
    /// True after `withhold()`, so a test can tell "nothing to show" from "not entitled".
    private(set) var isWithheld = false

    func publish(_ snapshot: RentalSummarySnapshot) {
        lock.lock(); defer { lock.unlock() }
        published = snapshot
        publishCount += 1
        isWithheld = false
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        published = nil
        isWithheld = false
    }

    func withhold() {
        lock.lock(); defer { lock.unlock() }
        published = nil
        isWithheld = true
    }
}
