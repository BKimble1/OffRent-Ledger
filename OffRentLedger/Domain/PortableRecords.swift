import Foundation

/// Codable mirrors of the persisted entities.
///
/// SwiftData `@Model` classes cannot be the export format: they are reference types tied to a
/// `ModelContext`, their `Codable` behaviour is not something to rely on across schema versions,
/// and an export file has to keep working after a migration that changes the store. So the store
/// maps to and from these, and everything that reads a backup — export, import preview, CSV, the
/// evidence packet — works on these instead.
///
/// The mapping lives in `Persistence/RecordMapping.swift`. These types are Foundation-only and
/// therefore testable without a store.

struct VendorRecord: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var branch: String?
    var phone: String?
    var email: String?
    var link: String?
    var standardNotes: String?
    var createdAt: Date
    var modifiedAt: Date
}

struct JobSiteRecord: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var projectIdentifier: String?
    var address: String?
    var notes: String?
    /// All three optional and all three decoded leniently, so a backup written before job sites
    /// had a place still imports.
    var placeName: String?
    var latitude: Double?
    var longitude: Double?
    var createdAt: Date
    var modifiedAt: Date

    init(
        id: UUID,
        name: String,
        projectIdentifier: String? = nil,
        address: String? = nil,
        notes: String? = nil,
        placeName: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        createdAt: Date,
        modifiedAt: Date
    ) {
        self.id = id
        self.name = name
        self.projectIdentifier = projectIdentifier
        self.address = address
        self.notes = notes
        self.placeName = placeName
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    /// A coordinate only when both halves are present.
    var coordinate: (latitude: Double, longitude: Double)? {
        guard let latitude, let longitude else { return nil }
        return (latitude, longitude)
    }
}

struct AgreementRecord: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var vendorID: UUID
    var jobSiteID: UUID?
    var agreementNumber: String?
    var startDate: Date
    var scheduledEndDate: Date?
    var disputeWindowDaysOverride: Int?
    var notes: String?
    var createdAt: Date
    var modifiedAt: Date
}

struct RentalItemRecord: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var agreementID: UUID
    var equipmentName: String
    var equipmentClass: String?
    var vendorEquipmentIdentifier: String?
    var serialNumber: String?
    var status: RentalItemStatus
    var terms: RentalTerms
    var meterUnit: MeterUnit
    var notes: String?
    var createdAt: Date
    var modifiedAt: Date
}

struct LocationSnapshotRecord: Codable, Sendable, Equatable {
    var latitude: Double
    var longitude: Double
    var horizontalAccuracyMetres: Double
    var capturedAt: Date
}

struct RentalEventRecord: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var itemID: UUID
    var type: RentalEventType
    var timestamp: Date
    var detail: String?
    var contactMethod: VendorContactMethod?
    var vendorRepresentative: String?
    var confirmationNumber: String?
    var locationSnapshot: LocationSnapshotRecord?
    var createdAt: Date
}

enum EvidenceMediaType: String, Codable, Sendable, CaseIterable {
    case image
    case pdf
    case other

    var displayName: String {
        switch self {
        case .image: "Photo"
        case .pdf: "PDF"
        case .other: "File"
        }
    }
}

enum EvidenceOwnerKind: String, Codable, Sendable {
    case agreement
    case item
    case event
    case invoice
}

struct EvidenceAssetRecord: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var ownerKind: EvidenceOwnerKind
    var ownerID: UUID
    /// Relative to the app's evidence directory. Never absolute: an absolute path is invalid the
    /// moment iOS reassigns the app's container, which it does on restore and on some updates.
    var relativePath: String
    var mediaType: EvidenceMediaType
    var displayName: String
    var capturedAt: Date
    var coordinate: LocationSnapshotRecord?
    var caption: String?
    /// SHA-256 of the file bytes.
    ///
    /// An integrity aid only: it tells the user whether the file they exported is the file they
    /// imported. It is not tamper-proof, not notarised, not a chain of custody and not evidence
    /// of anything legally. The UI says exactly that next to it.
    var sha256: String?
    var thumbnailRelativePath: String?
}

struct InvoiceRecord: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var agreementID: UUID
    var invoice: InvoiceValue
    var attachmentAssetID: UUID?
    var attachedAt: Date
    var reviewedAt: Date?
}

struct DiscrepancyRecord: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var invoiceID: UUID
    var itemID: UUID?
    var discrepancy: DiscrepancyValue
}
