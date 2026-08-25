import Foundation

/// The structured export format.
///
/// Versioned from the first release. A file written by v1 must still be readable by v3, so the
/// version is the first field and the importer refuses anything it does not understand rather
/// than doing its best with it.
struct BackupArchive: Codable, Sendable, Equatable {

    static let currentFormatVersion = 1

    var formatVersion: Int
    var generatedAt: Date
    var appVersion: String
    /// Whether the referenced evidence files travel alongside this file. A metadata-only backup
    /// is still useful and much smaller; the importer says plainly which one it is looking at.
    var includesEvidenceFiles: Bool

    var vendors: [VendorRecord]
    var jobSites: [JobSiteRecord]
    var agreements: [AgreementRecord]
    var items: [RentalItemRecord]
    var events: [RentalEventRecord]
    var assets: [EvidenceAssetRecord]
    var invoices: [InvoiceRecord]
    var discrepancies: [DiscrepancyRecord]

    init(
        formatVersion: Int = BackupArchive.currentFormatVersion,
        generatedAt: Date,
        appVersion: String,
        includesEvidenceFiles: Bool = false,
        vendors: [VendorRecord] = [],
        jobSites: [JobSiteRecord] = [],
        agreements: [AgreementRecord] = [],
        items: [RentalItemRecord] = [],
        events: [RentalEventRecord] = [],
        assets: [EvidenceAssetRecord] = [],
        invoices: [InvoiceRecord] = [],
        discrepancies: [DiscrepancyRecord] = []
    ) {
        self.formatVersion = formatVersion
        self.generatedAt = generatedAt
        self.appVersion = appVersion
        self.includesEvidenceFiles = includesEvidenceFiles
        self.vendors = vendors
        self.jobSites = jobSites
        self.agreements = agreements
        self.items = items
        self.events = events
        self.assets = assets
        self.invoices = invoices
        self.discrepancies = discrepancies
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Sorted keys make two exports of the same data byte-identical, which is what lets a user
        // diff them and what makes the round-trip test meaningful.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum BackupImportFailure: Error, Sendable, Equatable {
    case notJSON
    case unsupportedFormatVersion(found: Int, supported: Int)
    case corrupt(String)

    var message: String {
        switch self {
        case .notJSON:
            "That file is not an \(SharedBranding.displayName) backup."
        case let .unsupportedFormatVersion(found, supported):
            found > supported
                ? "That backup was written by a newer version of \(SharedBranding.displayName) (format \(found)). Update the app and try again."
                : "That backup uses an old format (\(found)) this version cannot read."
        case let .corrupt(detail):
            "That backup could not be read: \(detail)"
        }
    }
}

/// What an import *would* do, computed before anything is written.
///
/// The user sees this screen and presses Import, or does not. There is no code path that applies
/// an archive without producing one of these first.
struct ImportPreview: Sendable, Equatable {
    struct Counts: Sendable, Equatable {
        var vendors = 0
        var jobSites = 0
        var agreements = 0
        var items = 0
        var events = 0
        var invoices = 0
        var discrepancies = 0
        var assets = 0

        var total: Int {
            vendors + jobSites + agreements + items + events + invoices + discrepancies + assets
        }
    }

    var archiveGeneratedAt: Date
    var archiveAppVersion: String
    var formatVersion: Int
    var includesEvidenceFiles: Bool

    /// Records whose identifiers do not exist in the store yet.
    var willAdd: Counts
    /// Records whose identifiers already exist. **Skipped, never overwritten.** An import is
    /// additive: a user restoring an old backup must not lose work done since.
    var willSkipExisting: Counts
    /// Records that reference a parent the archive does not contain and the store does not have.
    var willSkipOrphaned: Counts
    /// Asset records whose files are not present. The metadata still imports; the attachment
    /// shows as missing rather than the whole import failing.
    var missingEvidenceFiles: [String]

    /// Attachments arriving as records with no file behind them, because the archive carries no
    /// files at all.
    ///
    /// `missingEvidenceFiles` above only ever populated when the archive *claimed* to carry
    /// files, and nothing has ever produced one that does — so a backup restored on a new phone
    /// created a photograph record for every photograph, each pointing at a file that will never
    /// exist, and said nothing. The user saw grey placeholders with a checksum printed under
    /// them and no explanation. This is the count that lets the import screen say it in advance.
    var assetsWithoutFiles: Int = 0

    var isEmpty: Bool { willAdd.total == 0 }

    var summary: String {
        if isEmpty { return "Nothing new to import. Everything in this backup is already here." }
        var parts: [String] = []
        func add(_ count: Int, _ singular: String, _ plural: String) {
            if count > 0 { parts.append("\(count) \(count == 1 ? singular : plural)") }
        }
        add(willAdd.vendors, "vendor", "vendors")
        add(willAdd.jobSites, "jobsite", "jobsites")
        add(willAdd.agreements, "agreement", "agreements")
        add(willAdd.items, "rental item", "rental items")
        add(willAdd.events, "timeline event", "timeline events")
        add(willAdd.invoices, "invoice", "invoices")
        add(willAdd.discrepancies, "possible mismatch", "possible mismatches")
        add(willAdd.assets, "attachment", "attachments")
        return "Will add " + parts.joined(separator: ", ") + "."
    }
}

/// Identifiers already present in the store, so the preview can be computed without the store
/// itself being visible to the domain layer.
struct ExistingIdentifiers: Sendable, Equatable {
    var vendors: Set<UUID> = []
    var jobSites: Set<UUID> = []
    var agreements: Set<UUID> = []
    var items: Set<UUID> = []
    var events: Set<UUID> = []
    var invoices: Set<UUID> = []
    var discrepancies: Set<UUID> = []
    var assets: Set<UUID> = []

    static let none = ExistingIdentifiers()
}

enum BackupImporter {

    static func decode(_ data: Data) -> Result<BackupArchive, BackupImportFailure> {
        // Read the version before decoding the body, so a newer file produces "update the app"
        // rather than a decoding error about a field the user has never heard of.
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.notJSON)
        }
        guard let version = object["formatVersion"] as? Int else {
            return .failure(.corrupt("no format version"))
        }
        guard version == BackupArchive.currentFormatVersion else {
            return .failure(
                .unsupportedFormatVersion(found: version, supported: BackupArchive.currentFormatVersion)
            )
        }
        do {
            return .success(try BackupArchive.decoder().decode(BackupArchive.self, from: data))
        } catch {
            return .failure(.corrupt(String(describing: error)))
        }
    }

    static func preview(
        archive: BackupArchive,
        existing: ExistingIdentifiers,
        availableEvidenceFiles: Set<String> = []
    ) -> ImportPreview {

        var add = ImportPreview.Counts()
        var skip = ImportPreview.Counts()
        var orphaned = ImportPreview.Counts()

        // Parents first, so a child can be checked against what this import will actually create.
        var knownVendors = existing.vendors
        var knownJobSites = existing.jobSites
        var knownAgreements = existing.agreements
        var knownItems = existing.items
        var knownInvoices = existing.invoices

        for vendor in archive.vendors {
            if existing.vendors.contains(vendor.id) { skip.vendors += 1 }
            else { add.vendors += 1; knownVendors.insert(vendor.id) }
        }
        for site in archive.jobSites {
            if existing.jobSites.contains(site.id) { skip.jobSites += 1 }
            else { add.jobSites += 1; knownJobSites.insert(site.id) }
        }
        for agreement in archive.agreements {
            if existing.agreements.contains(agreement.id) { skip.agreements += 1 }
            else if !knownVendors.contains(agreement.vendorID) { orphaned.agreements += 1 }
            else if let siteID = agreement.jobSiteID, !knownJobSites.contains(siteID) {
                orphaned.agreements += 1
            } else { add.agreements += 1; knownAgreements.insert(agreement.id) }
        }
        for item in archive.items {
            if existing.items.contains(item.id) { skip.items += 1 }
            else if !knownAgreements.contains(item.agreementID) { orphaned.items += 1 }
            else { add.items += 1; knownItems.insert(item.id) }
        }
        for event in archive.events {
            if existing.events.contains(event.id) { skip.events += 1 }
            else if !knownItems.contains(event.itemID) { orphaned.events += 1 }
            else { add.events += 1 }
        }
        for invoice in archive.invoices {
            if existing.invoices.contains(invoice.id) { skip.invoices += 1 }
            else if !knownAgreements.contains(invoice.agreementID) { orphaned.invoices += 1 }
            else { add.invoices += 1; knownInvoices.insert(invoice.id) }
        }
        for discrepancy in archive.discrepancies {
            if existing.discrepancies.contains(discrepancy.id) { skip.discrepancies += 1 }
            else if !knownInvoices.contains(discrepancy.invoiceID) { orphaned.discrepancies += 1 }
            else { add.discrepancies += 1 }
        }

        var missingFiles: [String] = []
        var withoutFiles = 0
        for asset in archive.assets {
            if existing.assets.contains(asset.id) { skip.assets += 1; continue }
            let ownerKnown: Bool = switch asset.ownerKind {
            case .agreement: knownAgreements.contains(asset.ownerID)
            case .item: knownItems.contains(asset.ownerID)
            case .event: true   // events are not individually addressable after import
            case .invoice: knownInvoices.contains(asset.ownerID)
            }
            guard ownerKnown else { orphaned.assets += 1; continue }
            add.assets += 1
            if archive.includesEvidenceFiles {
                if !availableEvidenceFiles.contains(asset.relativePath) {
                    missingFiles.append(asset.relativePath)
                }
            } else {
                withoutFiles += 1
            }
        }

        return ImportPreview(
            archiveGeneratedAt: archive.generatedAt,
            archiveAppVersion: archive.appVersion,
            formatVersion: archive.formatVersion,
            includesEvidenceFiles: archive.includesEvidenceFiles,
            willAdd: add,
            willSkipExisting: skip,
            willSkipOrphaned: orphaned,
            missingEvidenceFiles: missingFiles,
            assetsWithoutFiles: withoutFiles
        )
    }
}
