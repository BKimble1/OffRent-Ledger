import Foundation
import SwiftData

/// Fetch descriptors and derived reads, in one place.
///
/// Every predicate here filters in the store rather than in memory. That distinction is what
/// keeps Today responsive with a thousand rental items: `openItems()` fetches four rows, not four
/// thousand rows that are then filtered.
enum StoreQueries {

    // MARK: - Descriptors

    /// Items still needing something from the user, newest first.
    static func openItems() -> FetchDescriptor<RentalItem> {
        let closed = [RentalItemStatus.resolved.rawValue, RentalItemStatus.archived.rawValue]
        var descriptor = FetchDescriptor<RentalItem>(
            predicate: #Predicate { !closed.contains($0.statusRaw) },
            sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.agreement]
        return descriptor
    }

    static func items(withStatus status: RentalItemStatus) -> FetchDescriptor<RentalItem> {
        let raw = status.rawValue
        return FetchDescriptor<RentalItem>(
            predicate: #Predicate { $0.statusRaw == raw },
            sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
        )
    }

    static func items(withStatuses statuses: [RentalItemStatus]) -> FetchDescriptor<RentalItem> {
        let raw = statuses.map(\.rawValue)
        return FetchDescriptor<RentalItem>(
            predicate: #Predicate { raw.contains($0.statusRaw) },
            sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)]
        )
    }

    /// Items currently accruing an estimate.
    static func accruingItems() -> FetchDescriptor<RentalItem> {
        items(withStatuses: [.active, .contactVendor])
    }

    static func item(id: UUID) -> FetchDescriptor<RentalItem> {
        var descriptor = FetchDescriptor<RentalItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return descriptor
    }

    static func allItems() -> FetchDescriptor<RentalItem> {
        FetchDescriptor<RentalItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
    }

    static func allVendors() -> FetchDescriptor<Vendor> {
        FetchDescriptor<Vendor>(sortBy: [SortDescriptor(\.name)])
    }

    static func allJobSites() -> FetchDescriptor<JobSite> {
        FetchDescriptor<JobSite>(sortBy: [SortDescriptor(\.name)])
    }

    static func allAgreements() -> FetchDescriptor<RentalAgreement> {
        FetchDescriptor<RentalAgreement>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
    }

    static func invoicesAwaitingReview() -> FetchDescriptor<VendorInvoice> {
        let pending = [
            InvoiceReviewStatus.notReviewed.rawValue,
            InvoiceReviewStatus.inReview.rawValue,
        ]
        return FetchDescriptor<VendorInvoice>(
            predicate: #Predicate { pending.contains($0.reviewStatusRaw) },
            sortBy: [SortDescriptor(\.receivedDate, order: .reverse)]
        )
    }

    static func allInvoices() -> FetchDescriptor<VendorInvoice> {
        FetchDescriptor<VendorInvoice>(sortBy: [SortDescriptor(\.receivedDate, order: .reverse)])
    }

    static func invoice(id: UUID) -> FetchDescriptor<VendorInvoice> {
        var descriptor = FetchDescriptor<VendorInvoice>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return descriptor
    }

    static func openDiscrepancies() -> FetchDescriptor<Discrepancy> {
        let open = [DiscrepancyStatus.open.rawValue, DiscrepancyStatus.followUpRecorded.rawValue]
        return FetchDescriptor<Discrepancy>(
            predicate: #Predicate { open.contains($0.discrepancyStatusRaw) },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
    }

    static func allAssets() -> FetchDescriptor<EvidenceAsset> {
        FetchDescriptor<EvidenceAsset>()
    }

    // MARK: - Counting

    /// Items counting against the free-tier limit.
    ///
    /// A count, not a fetch. `fetchCount` asks the store for a number and never materialises the
    /// rows, which matters because this runs before every single item creation.
    static func openItemCount(in context: ModelContext) throws -> Int {
        try context.fetchCount(openItems())
    }
}
