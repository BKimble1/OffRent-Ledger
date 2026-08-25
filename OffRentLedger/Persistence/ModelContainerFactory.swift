import Foundation
import OSLog
import SwiftData

/// Builds the app's `ModelContainer`.
///
/// The failure path matters more than the happy one. A container that cannot open is usually a
/// store the app cannot read — a botched migration, a corrupt file, a downgrade. Crashing there
/// takes a contractor's rental records with it. So the factory reports the failure, and the app
/// shows a screen offering to export what can be read or to start fresh, rather than dying on
/// launch with no way out.
enum ModelContainerFactory {

    private static let logger = Logger(subsystem: "com.idlery.offrent", category: "persistence")

    enum Failure: Error {
        case couldNotOpenStore(underlying: String)
    }

    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: OffRentSchemaV3.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            // The app has no CloudKit container and no account. Saying so explicitly stops a
            // future capability change from silently switching sync on.
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: OffRentMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            // The error itself is safe to log — it describes the store, not its contents — but
            // it is marked private so a sysdiagnose from a user's device never carries a path
            // containing their name.
            logger.error("Model container failed to open: \(String(describing: error), privacy: .private)")
            throw Failure.couldNotOpenStore(underlying: String(describing: error))
        }
    }

    /// Used by previews and by the unit test suite. Never touches the user's store.
    static func makeInMemory() -> ModelContainer {
        // A failure here is a programmer error in a preview or a test, not something a user can
        // hit, and there is no sensible recovery.
        do {
            return try make(inMemory: true)
        } catch {
            fatalError("In-memory model container could not be created: \(error)")
        }
    }
}
