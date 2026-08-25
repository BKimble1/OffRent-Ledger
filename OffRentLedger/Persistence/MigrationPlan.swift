import Foundation
import SwiftData

/// The migration plan.
///
/// V1 shipped to TestFlight. V2 adds three optional attributes to `JobSiteModel` — a place name
/// and a coordinate. V3 adds three more: a contact name and a mailing address on `VendorModel`,
/// and a purchase-order number on `RentalAgreementModel`. Every one of them is optional, which
/// is precisely the shape SwiftData can migrate on its own. The stages are declared anyway
/// rather than left to the implicit path, so each upgrade is written down where a person can
/// read it.
///
/// A phone that skipped a build migrates V1 → V2 → V3 in order; SwiftData walks the stages.
/// That is why no earlier version is ever edited or deleted: each one is the description of a
/// store still sitting on somebody's phone, and without it there is nothing to migrate *from*.
///
/// When SchemaV4 arrives:
///   1. Copy `SchemaV3.swift` to `SchemaV4.swift` and change it there.
///   2. Move the `typealias`es to V4.
///   3. Append V4 to `schemas` and a `MigrationStage` to `stages`.
///   4. Add a round-trip test to `OffRentLedgerTests/MigrationTests`.
enum OffRentMigrationPlan: SchemaMigrationPlan {

    static var schemas: [any VersionedSchema.Type] {
        [OffRentSchemaV1.self, OffRentSchemaV2.self, OffRentSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [
            // Lightweight throughout: every added attribute is optional, so there is no value
            // to compute and no existing row that needs rewriting. Nothing here drops a column,
            // renames one, or deletes a row — a migration that loses a contractor's rental
            // history is the one failure this app cannot come back from.
            .lightweight(fromVersion: OffRentSchemaV1.self, toVersion: OffRentSchemaV2.self),
            .lightweight(fromVersion: OffRentSchemaV2.self, toVersion: OffRentSchemaV3.self),
        ]
    }
}
