import Foundation
import OSLog
import WidgetKit

/// Publishes the widget's summary snapshot.
protocol SnapshotPublishing: Sendable {
    func publish(_ snapshot: RentalSummarySnapshot)
    /// No rentals to show. The widget shows its "nothing here yet" state.
    func clear()
}

/// Writes the snapshot to the App Group and asks WidgetKit to reload.
///
/// The widget never opens the SwiftData store. It reads one small JSON blob that the app wrote,
/// which means a widget timeline refresh cannot migrate the store, cannot lock it against the
/// app, and cannot fail in a way the user would have to debug. It also means the widget is
/// structurally incapable of seeing anything `RentalSummarySnapshot` cannot carry — no vendor, no
/// jobsite, no address, no agreement number, no invoice amount.
///
/// Nothing here is gated on the subscription. It used to be, and the result was a widget that
/// could not work: `EntitlementPolicy`'s governing rule is that entitlement gates *creating*
/// rentals and never *seeing* the ones you already have, and a widget is nothing but seeing.
struct AppGroupSnapshotPublisher: SnapshotPublishing {

    private static let logger = Logger(subsystem: "com.idlery.offrent", category: "widget")

    func publish(_ snapshot: RentalSummarySnapshot) {
        guard let defaults = sharedDefaults(for: "publish") else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else {
            Self.logger.error("Could not encode the widget snapshot")
            return
        }
        defaults.set(data, forKey: SharedIdentifiers.snapshotDefaultsKey)
        removeRetiredKeys(from: defaults)
        reload()
    }

    func clear() {
        guard let defaults = sharedDefaults(for: "clear") else { return }
        defaults.removeObject(forKey: SharedIdentifiers.snapshotDefaultsKey)
        removeRetiredKeys(from: defaults)
        reload()
    }

    /// Logs when the App Group is missing instead of returning quietly.
    ///
    /// `clear()` and its since-removed sibling used to `guard ... else { return }` with nothing
    /// written anywhere, so an App Group the build was not entitled to produced a widget stuck on
    /// "Open the app to start tracking a rental" and no evidence anywhere of why.
    private func sharedDefaults(for operation: String) -> UserDefaults? {
        guard let defaults = UserDefaults(suiteName: SharedIdentifiers.appGroupIdentifier) else {
            Self.logger.error(
                "App Group \(SharedIdentifiers.appGroupIdentifier, privacy: .public) unavailable — widget \(operation, privacy: .public) did nothing"
            )
            return nil
        }
        return defaults
    }

    /// Blobs older builds wrote. Left behind they are only wasted bytes, but they are also the
    /// kind of thing that makes a stale-data bug take a day to find.
    private func removeRetiredKeys(from defaults: UserDefaults) {
        for key in SharedIdentifiers.retiredSnapshotDefaultsKeys {
            defaults.removeObject(forKey: key)
        }
    }

    private func reload() {
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

    func publish(_ snapshot: RentalSummarySnapshot) {
        lock.lock(); defer { lock.unlock() }
        published = snapshot
        publishCount += 1
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        published = nil
    }
}
