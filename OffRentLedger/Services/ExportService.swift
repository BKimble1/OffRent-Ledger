import Foundation
import OSLog
import SwiftData

/// Assembles exports and applies imports.
///
/// Everything it produces is built from the Foundation-only records, so the formats are decided
/// and tested in `Domain` and this file only moves bytes.
@MainActor
struct ExportService {

    private static let logger = Logger(subsystem: "com.idlery.offrent", category: "export")

    let context: ModelContext
    let clock: any Clock
    let fileStore: any FileStoring

    // MARK: - Export

    func buildArchive(includeEvidenceFiles: Bool = false) throws -> BackupArchive {
        let vendors = try context.fetch(StoreQueries.allVendors())
        let sites = try context.fetch(StoreQueries.allJobSites())
        let agreements = try context.fetch(StoreQueries.allAgreements())
        let items = try context.fetch(StoreQueries.allItems())
        let invoices = try context.fetch(StoreQueries.allInvoices())
        let assets = try context.fetch(StoreQueries.allAssets())

        let events = items.flatMap { $0.sortedEvents }
        let discrepancies = invoices.flatMap { $0.discrepancies ?? [] }

        // Each list is hoisted into an annotated local rather than mapped inline in the
        // initialiser call. Eight generic `map`/`compactMap` calls in a single expression is the
        // shape that makes the type checker give up ("unable to type-check in reasonable time");
        // annotating each result leaves it nothing to solve for.
        //
        // `compactMap`: a record whose parent relationship is nil cannot be expressed in the
        // archive and is dropped rather than exported with a fabricated parent.
        let vendorRecords: [VendorRecord] = vendors.map(\.record)
        let jobSiteRecords: [JobSiteRecord] = sites.map(\.record)
        let agreementRecords: [AgreementRecord] = agreements.compactMap(\.record)
        let itemRecords: [RentalItemRecord] = items.compactMap(\.record)
        let eventRecords: [RentalEventRecord] = events.compactMap(\.record)
        let assetRecords: [EvidenceAssetRecord] = assets.map(\.record)
        let invoiceRecords: [InvoiceRecord] = invoices.compactMap(\.record)
        let discrepancyRecords: [DiscrepancyRecord] = discrepancies.compactMap(\.record)

        return BackupArchive(
            generatedAt: clock.now,
            appVersion: AppConfiguration.versionAndBuild,
            includesEvidenceFiles: includeEvidenceFiles,
            vendors: vendorRecords,
            jobSites: jobSiteRecords,
            agreements: agreementRecords,
            items: itemRecords,
            events: eventRecords,
            assets: assetRecords,
            invoices: invoiceRecords,
            discrepancies: discrepancyRecords
        )
    }

    func encodeArchive(includeEvidenceFiles: Bool = false) throws -> Data {
        try BackupArchive.encoder().encode(buildArchive(includeEvidenceFiles: includeEvidenceFiles))
    }

    /// CSV for every rental item, or for one.
    func makeCSV(items: [RentalItem]) -> String {
        CSVExport.makeCSV(
            rows: items.map { summaryRow(for: $0) },
            calendar: clock.calendar
        )
    }

    func makeCSVForAllItems() throws -> String {
        makeCSV(items: try context.fetch(StoreQueries.allItems()))
    }

    private func summaryRow(for item: RentalItem) -> RentalSummaryRow {
        let agreement = item.agreement
        let estimate = RentalRateEngine.estimate(
            terms: item.terms, asOf: clock.now, calendar: clock.calendar
        )
        let confirmation = item.sortedEvents.last { $0.type == .vendorConfirmationRecorded }
        let pickup = item.sortedEvents.last { $0.type == .pickupRecorded }
        let invoice: VendorInvoice? = item.latestInvoice

        var variance: Decimal?
        var openCount = 0
        if let invoice {
            let comparison = InvoiceComparisonEngine.compare(
                InvoiceComparisonInput(
                    terms: item.terms,
                    confirmationDate: confirmation?.timestamp,
                    pickupDate: pickup?.timestamp,
                    invoice: invoice.value,
                    expectedRentalSubtotalOverride: invoice.expectedRentalSubtotalOverride,
                    calendar: clock.calendar,
                    now: clock.now
                )
            )
            variance = comparison.possibleVariance
            openCount = invoice.openDiscrepancyCount
        }

        return RentalSummaryRow(
            vendorName: agreement?.vendor?.name ?? "Unknown vendor",
            vendorBranch: agreement?.vendor?.branch,
            jobSiteName: agreement?.jobSite?.name,
            agreementNumber: agreement?.agreementNumber,
            equipmentName: item.equipmentName,
            vendorEquipmentIdentifier: item.vendorEquipmentIdentifier,
            status: item.status,
            deliveryDate: item.deliveryDate,
            billingBasis: item.terms.billingBasis,
            dailyRate: item.dailyRate,
            weeklyRate: item.weeklyRate,
            fourWeekRate: item.fourWeekRate,
            nextRolloverDate: RentalRateEngine.nextRollover(
                terms: item.terms, asOf: clock.now, calendar: clock.calendar
            )?.date,
            estimatedRunningCost: estimate.isComplete ? estimate.estimatedTotal : nil,
            estimateIsComplete: estimate.isComplete,
            confirmationNumber: confirmation?.confirmationNumber,
            confirmationRecordedAt: confirmation?.timestamp,
            pickupRecordedAt: pickup?.timestamp,
            invoiceNumber: invoice?.invoiceNumber,
            invoiceTotal: invoice?.invoiceTotal,
            possibleVariance: variance,
            openMismatchCount: openCount,
            notes: item.notes
        )
    }

    // MARK: - Import

    func existingIdentifiers() throws -> ExistingIdentifiers {
        // Fetches and identifier sets are separate annotated steps for the same reason as
        // `buildArchive` above: eight `Set(...).map(\.id)` conversions inside one initialiser
        // call is a type-checker blowup waiting to happen, and `try` inside an argument list
        // reads worse than it does on its own line.
        let vendors = try context.fetch(StoreQueries.allVendors())
        let sites = try context.fetch(StoreQueries.allJobSites())
        let agreements = try context.fetch(StoreQueries.allAgreements())
        let items = try context.fetch(StoreQueries.allItems())
        let invoices = try context.fetch(StoreQueries.allInvoices())
        let assets = try context.fetch(StoreQueries.allAssets())

        var eventIDs: Set<UUID> = []
        for item in items {
            for event in item.sortedEvents { eventIDs.insert(event.id) }
        }
        var discrepancyIDs: Set<UUID> = []
        for invoice in invoices {
            for discrepancy in invoice.discrepancies ?? [] { discrepancyIDs.insert(discrepancy.id) }
        }

        let vendorIDs: Set<UUID> = Set(vendors.map(\.id))
        let jobSiteIDs: Set<UUID> = Set(sites.map(\.id))
        let agreementIDs: Set<UUID> = Set(agreements.map(\.id))
        let itemIDs: Set<UUID> = Set(items.map(\.id))
        let invoiceIDs: Set<UUID> = Set(invoices.map(\.id))
        let assetIDs: Set<UUID> = Set(assets.map(\.id))

        return ExistingIdentifiers(
            vendors: vendorIDs,
            jobSites: jobSiteIDs,
            agreements: agreementIDs,
            items: itemIDs,
            events: eventIDs,
            invoices: invoiceIDs,
            discrepancies: discrepancyIDs,
            assets: assetIDs
        )
    }

    func preview(archiveData: Data) throws -> Result<(BackupArchive, ImportPreview), BackupImportFailure> {
        switch BackupImporter.decode(archiveData) {
        case let .failure(failure):
            return .failure(failure)
        case let .success(archive):
            let preview = BackupImporter.preview(
                archive: archive, existing: try existingIdentifiers()
            )
            return .success((archive, preview))
        }
    }

    /// Applies an archive. **Additive only.**
    ///
    /// A record whose identifier already exists is skipped, never overwritten. Restoring a backup
    /// from three weeks ago must not delete the three weeks of work that followed it, and a user
    /// who has just tapped Import cannot be expected to have thought that through.
    @discardableResult
    func apply(archive: BackupArchive) throws -> ImportPreview {
        let existing = try existingIdentifiers()
        let preview = BackupImporter.preview(archive: archive, existing: existing)

        var vendorsByID: [UUID: Vendor] = [:]
        for vendor in try context.fetch(StoreQueries.allVendors()) { vendorsByID[vendor.id] = vendor }
        for record in archive.vendors where !existing.vendors.contains(record.id) {
            let vendor = Vendor(record: record)
            context.insert(vendor)
            vendorsByID[record.id] = vendor
        }

        var sitesByID: [UUID: JobSite] = [:]
        for site in try context.fetch(StoreQueries.allJobSites()) { sitesByID[site.id] = site }
        for record in archive.jobSites where !existing.jobSites.contains(record.id) {
            let site = JobSite(record: record)
            context.insert(site)
            sitesByID[record.id] = site
        }

        var agreementsByID: [UUID: RentalAgreement] = [:]
        for agreement in try context.fetch(StoreQueries.allAgreements()) {
            agreementsByID[agreement.id] = agreement
        }
        for record in archive.agreements where !existing.agreements.contains(record.id) {
            guard let vendor = vendorsByID[record.vendorID] else { continue }
            let agreement = RentalAgreement(
                id: record.id, agreementNumber: record.agreementNumber,
                purchaseOrderNumber: record.purchaseOrderNumber,
                startDate: record.startDate, scheduledEndDate: record.scheduledEndDate,
                disputeWindowDaysOverride: record.disputeWindowDaysOverride, notes: record.notes,
                createdAt: record.createdAt, modifiedAt: record.modifiedAt,
                vendor: vendor, jobSite: record.jobSiteID.flatMap { sitesByID[$0] }
            )
            context.insert(agreement)
            agreementsByID[record.id] = agreement
        }

        var itemsByID: [UUID: RentalItem] = [:]
        for item in try context.fetch(StoreQueries.allItems()) { itemsByID[item.id] = item }
        for record in archive.items where !existing.items.contains(record.id) {
            guard let agreement = agreementsByID[record.agreementID] else { continue }
            let item = RentalItem(
                id: record.id, equipmentName: record.equipmentName,
                equipmentClass: record.equipmentClass,
                vendorEquipmentIdentifier: record.vendorEquipmentIdentifier,
                serialNumber: record.serialNumber, status: record.status, terms: record.terms,
                meterUnit: record.meterUnit, notes: record.notes,
                createdAt: record.createdAt, modifiedAt: record.modifiedAt, agreement: agreement
            )
            context.insert(item)
            itemsByID[record.id] = item
        }

        for record in archive.events where !existing.events.contains(record.id) {
            guard let item = itemsByID[record.itemID] else { continue }
            context.insert(
                RentalEvent(
                    id: record.id, type: record.type, timestamp: record.timestamp,
                    detail: record.detail, contactMethod: record.contactMethod,
                    vendorRepresentative: record.vendorRepresentative,
                    confirmationNumber: record.confirmationNumber,
                    meterReading: record.meterReading, fuelLevel: record.fuelLevel,
                    location: record.locationSnapshot, createdAt: record.createdAt, item: item
                )
            )
        }

        var invoicesByID: [UUID: VendorInvoice] = [:]
        for invoice in try context.fetch(StoreQueries.allInvoices()) { invoicesByID[invoice.id] = invoice }
        for record in archive.invoices where !existing.invoices.contains(record.id) {
            guard let agreement = agreementsByID[record.agreementID] else { continue }
            let invoice = VendorInvoice(
                id: record.id, invoiceNumber: record.invoice.invoiceNumber,
                receivedDate: record.invoice.receivedDate,
                billedThroughDate: record.invoice.billedThroughDate,
                invoiceTotal: record.invoice.invoiceTotal,
                reviewStatus: record.invoice.reviewStatus, notes: record.invoice.notes,
                attachedAt: record.attachedAt, reviewedAt: record.reviewedAt,
                agreement: agreement
            )
            context.insert(invoice)
            for (index, line) in record.invoice.lines.enumerated() {
                context.insert(InvoiceLine(value: line, sortIndex: index, invoice: invoice))
            }
            invoicesByID[record.id] = invoice
        }

        for record in archive.discrepancies where !existing.discrepancies.contains(record.id) {
            guard let invoice = invoicesByID[record.invoiceID] else { continue }
            context.insert(
                Discrepancy(value: record.discrepancy, itemID: record.itemID, invoice: invoice)
            )
        }

        // Asset *metadata* imports even when the file is absent; the attachment then shows as
        // missing rather than the whole import failing on one deleted photo.
        for record in archive.assets where !existing.assets.contains(record.id) {
            let asset = EvidenceAsset(
                id: record.id, relativePath: record.relativePath, mediaType: record.mediaType,
                displayName: record.displayName, capturedAt: record.capturedAt,
                caption: record.caption, sha256: record.sha256,
                thumbnailRelativePath: record.thumbnailRelativePath, location: record.coordinate,
                agreement: record.ownerKind == .agreement ? agreementsByID[record.ownerID] : nil,
                item: record.ownerKind == .item ? itemsByID[record.ownerID] : nil,
                invoice: record.ownerKind == .invoice ? invoicesByID[record.ownerID] : nil,
                eventID: record.ownerKind == .event ? record.ownerID : nil
            )
            context.insert(asset)
        }

        try context.save()
        Self.logger.info("Import applied: \(preview.willAdd.total, privacy: .public) records added")
        return preview
    }

    // MARK: - Deletion

    /// Removes every record and every file. Never gated behind a subscription.
    func deleteAllData() async throws {
        for item in try context.fetch(StoreQueries.allItems()) { context.delete(item) }
        for invoice in try context.fetch(StoreQueries.allInvoices()) { context.delete(invoice) }
        for agreement in try context.fetch(StoreQueries.allAgreements()) { context.delete(agreement) }
        for site in try context.fetch(StoreQueries.allJobSites()) { context.delete(site) }
        for vendor in try context.fetch(StoreQueries.allVendors()) { context.delete(vendor) }
        for asset in try context.fetch(StoreQueries.allAssets()) { context.delete(asset) }
        try context.save()
        try await fileStore.deleteAllEvidence()
    }

    /// Sweeps evidence files no record points at.
    @discardableResult
    func reconcileEvidenceFiles() async throws -> [String] {
        let assets = try context.fetch(StoreQueries.allAssets())
        var referenced = Set(assets.map(\.relativePath))
        referenced.formUnion(assets.compactMap(\.thumbnailRelativePath))
        return await fileStore.reconcile(referencedPaths: referenced)
    }
}
