import Foundation
import SwiftData
import Testing
@testable import OffRentLedger

/// Schema V2 — job sites that know where they are.
///
/// The check that matters is not that a new store works; it is that the three attributes are
/// genuinely optional everywhere, so a job site created before this version existed is still a
/// valid job site afterwards. A migration that requires a value is a migration that loses rows.
@MainActor
struct MigrationTests {

    private func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainerFactory.make(inMemory: true))
    }

    @Test func theContainerOpensOnTheCurrentSchema() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        #expect(container.schema.version == Schema.Version(2, 0, 0))
    }

    @Test func theMigrationPlanStillDescribesTheVersionItIsMigratingFrom() {
        let versions = OffRentMigrationPlan.schemas.map { $0.versionIdentifier }
        #expect(versions.contains(Schema.Version(1, 0, 0)), "V1 describes stores already on phones")
        #expect(versions.contains(Schema.Version(2, 0, 0)))
        #expect(OffRentMigrationPlan.stages.count == 1)
    }

    @Test func aJobSiteWithNoPlaceIsStillAJobSite() throws {
        let context = try makeContext()
        let now = Date(timeIntervalSince1970: 1_778_000_000)
        let site = JobSite(name: "Ridgeline Phase 2", createdAt: now, modifiedAt: now)
        context.insert(site)
        try context.save()

        #expect(site.placeName == nil)
        #expect(site.latitude == nil)
        #expect(site.longitude == nil)
        #expect(site.coordinate == nil, "half a coordinate is not a place, and neither is none")
    }

    @Test func aChosenPlaceSurvivesASave() throws {
        let context = try makeContext()
        let now = Date(timeIntervalSince1970: 1_778_000_000)
        let site = JobSite(
            name: "Ridgeline Phase 2",
            address: "1400 Ridgeline Dr, Plano, TX 75024",
            placeName: "Ridgeline Business Park",
            latitude: 33.0198,
            longitude: -96.6989,
            createdAt: now,
            modifiedAt: now
        )
        context.insert(site)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<JobSite>()).first
        #expect(fetched?.placeName == "Ridgeline Business Park")
        #expect(fetched?.coordinate?.latitude == 33.0198)
        #expect(fetched?.coordinate?.longitude == -96.6989)
    }

    /// One half of a coordinate is a bug somewhere upstream, and the map must not draw a pin in
    /// the Atlantic because of it.
    @Test func halfACoordinateIsNoCoordinate() throws {
        let context = try makeContext()
        let now = Date(timeIntervalSince1970: 1_778_000_000)
        let site = JobSite(name: "Half", latitude: 33.0198, createdAt: now, modifiedAt: now)
        context.insert(site)
        try context.save()
        #expect(site.coordinate == nil)
    }

    @Test func theBackupRecordCarriesThePlaceBothWays() throws {
        let now = Date(timeIntervalSince1970: 1_778_000_000)
        let original = JobSite(
            name: "Ridgeline Phase 2",
            placeName: "Ridgeline Business Park",
            latitude: 33.0198,
            longitude: -96.6989,
            createdAt: now,
            modifiedAt: now
        )
        let record = original.record
        #expect(record.coordinate?.latitude == 33.0198)

        let encoded = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(JobSiteRecord.self, from: encoded)
        #expect(decoded == record)

        let rebuilt = JobSite(record: decoded)
        #expect(rebuilt.placeName == "Ridgeline Business Park")
        #expect(rebuilt.coordinate?.longitude == -96.6989)
    }

    /// A backup written before job sites had a place still imports. Decoding that blob is what a
    /// user does when they restore an old file, and it must not throw.
    @Test func aBackupWrittenBeforePlacesExistedStillDecodes() throws {
        let legacy = """
            {
              "id": "6C2E1C7E-6B0F-4C9E-9E39-5C8B7F1A2D34",
              "name": "Ridgeline Phase 2",
              "createdAt": 741484800,
              "modifiedAt": 741484800
            }
            """
        let decoded = try JSONDecoder().decode(JobSiteRecord.self, from: Data(legacy.utf8))
        #expect(decoded.name == "Ridgeline Phase 2")
        #expect(decoded.placeName == nil)
        #expect(decoded.coordinate == nil)
    }
}
