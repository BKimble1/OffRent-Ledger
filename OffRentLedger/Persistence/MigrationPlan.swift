import Foundation
import SwiftData

/// The migration plan, in place before v1 ships.
///
/// It has one schema and no stages today. That is the point: the plan, the `VersionedSchema` and
/// the container's use of them all exist and are exercised from the first release, so adding
/// SchemaV2 later is appending two lines rather than retrofitting versioning onto a store full of
/// customers' rental records.
///
/// When SchemaV2 arrives:
///   1. Copy `OffRentSchemaV1` to `OffRentSchemaV2` and change it there.
///   2. Point the `typealias`es at V2.
///   3. Append V2 to `schemas` and a `MigrationStage` to `stages`.
///   4. Add a round-trip test to `OffRentLedgerTests/MigrationTests`.
enum OffRentMigrationPlan: SchemaMigrationPlan {

    static var schemas: [any VersionedSchema.Type] {
        [OffRentSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
