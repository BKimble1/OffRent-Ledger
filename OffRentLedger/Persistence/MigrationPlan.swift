import Foundation
import SwiftData

/// The migration plan.
///
/// V1 shipped to TestFlight. V2 adds three optional attributes to `JobSiteModel` — a place name
/// and a coordinate — and changes nothing else, which is precisely the shape SwiftData can
/// migrate on its own. The stage is declared anyway rather than left to the implicit path, so
/// the upgrade is written down somewhere a person can read it.
///
/// V1 stays in the repository, frozen. It is not dead code: it is the description of the store
/// sitting on the phone of anybody who has not opened the new build yet, and without it there is
/// nothing to migrate *from*.
///
/// When SchemaV3 arrives:
///   1. Copy `SchemaV2.swift` to `SchemaV3.swift` and change it there.
///   2. Move the `typealias`es to V3.
///   3. Append V3 to `schemas` and a `MigrationStage` to `stages`.
///   4. Add a round-trip test to `OffRentLedgerTests/MigrationTests`.
enum OffRentMigrationPlan: SchemaMigrationPlan {

    static var schemas: [any VersionedSchema.Type] {
        [OffRentSchemaV1.self, OffRentSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [
            // Lightweight: every added attribute is optional, so there is no value to compute
            // and no existing row that needs rewriting.
            .lightweight(fromVersion: OffRentSchemaV1.self, toVersion: OffRentSchemaV2.self),
        ]
    }
}
