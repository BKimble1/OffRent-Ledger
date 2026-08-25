import Foundation
import OSLog
import SwiftData

/// Saving, with the failure kept rather than thrown away.
///
/// `try? context.save()` appeared in two dozen places. SwiftData saves rarely fail — but when one
/// does, because the disk is full or the store has been taken away mid-write, `try?` discarded
/// the error, the sheet dismissed, and the user was left looking at a screen that said their
/// confirmation number had been filed. In a ledger somebody intends to put in front of a rental
/// company, a record that silently is not there is the worst thing this app can produce.
///
/// Two entry points, because not every save is equal:
///
/// * `save(_:describing:)` is for anything the user typed. It returns a sentence to show them.
/// * `saveDerived(_:describing:)` is for caches and derived state the app can recompute on the
///   next launch. It logs and moves on, because interrupting somebody to report that a cached
///   estimate did not persist would be noise.
@MainActor
enum PersistentStore {

    private static let logger = Logger(subsystem: "com.idlery.offrent", category: "persistence")

    /// Attempts the save. Returns `nil` when the record is safely on disk, or a sentence for the
    /// user when it is not.
    ///
    /// - Parameter subject: what was being saved, as a noun phrase that can start a sentence —
    ///   "This confirmation", "The rental", "Your changes".
    @discardableResult
    static func save(_ context: ModelContext, describing subject: String) -> String? {
        guard context.hasChanges else { return nil }
        do {
            try context.save()
            return nil
        } catch {
            // The error text itself is Apple's and is not written for a contractor standing in a
            // yard, so it goes to the log and the user gets a sentence they can act on.
            logger.error("Save failed for \(subject, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return "\(subject) could not be saved. Check that your iPhone has free storage, then try again. Nothing you entered has been lost from this screen."
        }
    }

    /// For caches and derived values, which the app recomputes anyway.
    static func saveDerived(_ context: ModelContext, describing subject: String) {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            logger.error("Derived save failed for \(subject, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
