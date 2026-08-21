import Foundation
import SwiftData

/// Version 1 of the persisted schema.
///
/// Versioned from the first release rather than "when we need it". A `VersionedSchema` added
/// later cannot describe the store that already shipped, so v1 has to exist before v1 ships.
///
/// Two rules shape these types:
///
/// 1. **Nothing important is stored in an unqueryable blob.** Rates, dates, statuses and billing
///    bases are columns, not an encoded `RentalTerms`. The domain value types are reconstructed
///    from them on read. That is more code, and it is what lets Today fetch "items awaiting
///    pickup" with a predicate instead of loading every rental and filtering in memory.
/// 2. **Enums are stored as their raw strings.** A stored enum case that is later renamed takes
///    the store with it; a raw string is inspectable, migratable and survives a typo in a way an
///    opaque encoding does not.
enum OffRentSchemaV1: VersionedSchema {

    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            VendorModel.self,
            JobSiteModel.self,
            RentalAgreementModel.self,
            RentalItemModel.self,
            RentalEventModel.self,
            EvidenceAssetModel.self,
            VendorInvoiceModel.self,
            InvoiceLineModel.self,
            DiscrepancyModel.self,
        ]
    }

    // MARK: - Vendor

    @Model
    final class VendorModel {
        var id: UUID = UUID()
        var name: String = ""
        var branch: String?
        var phone: String?
        var email: String?
        var link: String?
        var standardNotes: String?
        var createdAt: Date = Date()
        var modifiedAt: Date = Date()

        /// Deleting a vendor deletes its agreements, and through them its items, events and
        /// attachments. `AppFileStore.reconcile` then sweeps the orphaned files.
        @Relationship(deleteRule: .cascade, inverse: \RentalAgreementModel.vendor)
        var agreements: [RentalAgreementModel]? = []

        init(
            id: UUID = UUID(),
            name: String,
            branch: String? = nil,
            phone: String? = nil,
            email: String? = nil,
            link: String? = nil,
            standardNotes: String? = nil,
            createdAt: Date,
            modifiedAt: Date
        ) {
            self.id = id
            self.name = name
            self.branch = branch
            self.phone = phone
            self.email = email
            self.link = link
            self.standardNotes = standardNotes
            self.createdAt = createdAt
            self.modifiedAt = modifiedAt
            self.agreements = []
        }
    }

    // MARK: - Jobsite

    @Model
    final class JobSiteModel {
        var id: UUID = UUID()
        var name: String = ""
        var projectIdentifier: String?
        var address: String?
        var notes: String?
        var createdAt: Date = Date()
        var modifiedAt: Date = Date()

        /// Nullify, not cascade. A jobsite is a label; deleting "Ridgeline Phase 2" must not take
        /// the rentals that happened there with it.
        @Relationship(deleteRule: .nullify, inverse: \RentalAgreementModel.jobSite)
        var agreements: [RentalAgreementModel]? = []

        init(
            id: UUID = UUID(),
            name: String,
            projectIdentifier: String? = nil,
            address: String? = nil,
            notes: String? = nil,
            createdAt: Date,
            modifiedAt: Date
        ) {
            self.id = id
            self.name = name
            self.projectIdentifier = projectIdentifier
            self.address = address
            self.notes = notes
            self.createdAt = createdAt
            self.modifiedAt = modifiedAt
            self.agreements = []
        }
    }

    // MARK: - Agreement

    @Model
    final class RentalAgreementModel {
        var id: UUID = UUID()
        var agreementNumber: String?
        var startDate: Date = Date()
        var scheduledEndDate: Date?
        /// Overrides `ReminderSettings.defaultDisputeWindowDays` for this vendor's paperwork.
        var disputeWindowDaysOverride: Int?
        var notes: String?
        var createdAt: Date = Date()
        var modifiedAt: Date = Date()

        var vendor: VendorModel?
        var jobSite: JobSiteModel?

        @Relationship(deleteRule: .cascade, inverse: \RentalItemModel.agreement)
        var items: [RentalItemModel]? = []

        @Relationship(deleteRule: .cascade, inverse: \VendorInvoiceModel.agreement)
        var invoices: [VendorInvoiceModel]? = []

        @Relationship(deleteRule: .cascade, inverse: \EvidenceAssetModel.agreement)
        var assets: [EvidenceAssetModel]? = []

        init(
            id: UUID = UUID(),
            agreementNumber: String? = nil,
            startDate: Date,
            scheduledEndDate: Date? = nil,
            disputeWindowDaysOverride: Int? = nil,
            notes: String? = nil,
            createdAt: Date,
            modifiedAt: Date,
            vendor: VendorModel? = nil,
            jobSite: JobSiteModel? = nil
        ) {
            self.id = id
            self.agreementNumber = agreementNumber
            self.startDate = startDate
            self.scheduledEndDate = scheduledEndDate
            self.disputeWindowDaysOverride = disputeWindowDaysOverride
            self.notes = notes
            self.createdAt = createdAt
            self.modifiedAt = modifiedAt
            self.vendor = vendor
            self.jobSite = jobSite
            self.items = []
            self.invoices = []
            self.assets = []
        }
    }

    // MARK: - Rental item

    @Model
    final class RentalItemModel {
        var id: UUID = UUID()
        var equipmentName: String = ""
        var equipmentClass: String?
        var vendorEquipmentIdentifier: String?
        var serialNumber: String?

        /// Raw string, never a stored enum. Assigned only by `RentalWorkflowService`.
        var statusRaw: String = RentalItemStatus.draft.rawValue

        // Terms, flattened so they can be queried and so a schema change is a column rather than
        // a re-encode of every row.
        var deliveryDate: Date = Date()
        var dailyRate: Decimal?
        var weeklyRate: Decimal?
        var fourWeekRate: Decimal?
        var billingBasisRaw: String = BillingBasis.daily.rawValue
        var rolloverModeRaw: String = RolloverMode.manual.rawValue
        var nextRolloverDate: Date?
        var expectedNextIncrement: Decimal?
        var subsequentIntervalDays: Int?
        var manualRolloverOverride: Bool = false
        var includedUsageNotes: String?
        var accrualStoppedAt: Date?

        var meterUnitRaw: String = MeterUnit.hours.rawValue
        var notes: String?
        var createdAt: Date = Date()
        var modifiedAt: Date = Date()

        /// Cached so the rentals list and the widget snapshot do not recompute an estimate per
        /// row while scrolling. Refreshed by `RentalWorkflowService.refreshEstimate`; the
        /// authoritative figure is always `RentalRateEngine`.
        var cachedEstimatedRunningCost: Decimal?
        var cachedEstimateIsComplete: Bool = false
        var cachedEstimateAsOf: Date?

        var agreement: RentalAgreementModel?

        @Relationship(deleteRule: .cascade, inverse: \RentalEventModel.item)
        var events: [RentalEventModel]? = []

        @Relationship(deleteRule: .cascade, inverse: \EvidenceAssetModel.item)
        var assets: [EvidenceAssetModel]? = []

        init(
            id: UUID = UUID(),
            equipmentName: String,
            equipmentClass: String? = nil,
            vendorEquipmentIdentifier: String? = nil,
            serialNumber: String? = nil,
            status: RentalItemStatus = .draft,
            terms: RentalTerms,
            meterUnit: MeterUnit = .hours,
            notes: String? = nil,
            createdAt: Date,
            modifiedAt: Date,
            agreement: RentalAgreementModel? = nil
        ) {
            self.id = id
            self.equipmentName = equipmentName
            self.equipmentClass = equipmentClass
            self.vendorEquipmentIdentifier = vendorEquipmentIdentifier
            self.serialNumber = serialNumber
            self.statusRaw = status.rawValue
            self.deliveryDate = terms.deliveryDate
            self.dailyRate = terms.rateCard.daily
            self.weeklyRate = terms.rateCard.weekly
            self.fourWeekRate = terms.rateCard.fourWeek
            self.billingBasisRaw = terms.billingBasis.rawValue
            self.rolloverModeRaw = terms.rolloverMode.rawValue
            self.nextRolloverDate = terms.nextRolloverDate
            self.expectedNextIncrement = terms.expectedNextIncrement
            self.subsequentIntervalDays = terms.subsequentIntervalDays
            self.manualRolloverOverride = terms.manualRolloverOverride
            self.includedUsageNotes = terms.includedUsageNotes
            self.accrualStoppedAt = terms.accrualStoppedAt
            self.meterUnitRaw = meterUnit.rawValue
            self.notes = notes
            self.createdAt = createdAt
            self.modifiedAt = modifiedAt
            self.agreement = agreement
            self.events = []
            self.assets = []
        }

        /// An unrecognised raw value degrades to `.draft` rather than crashing. A store written by
        /// a newer build, restored onto an older one, must not take the app down.
        var status: RentalItemStatus {
            RentalItemStatus(rawValue: statusRaw) ?? .draft
        }

        var meterUnit: MeterUnit { MeterUnit(rawValue: meterUnitRaw) ?? .hours }

        var terms: RentalTerms {
            get {
                RentalTerms(
                    deliveryDate: deliveryDate,
                    rateCard: RateCard(daily: dailyRate, weekly: weeklyRate, fourWeek: fourWeekRate),
                    billingBasis: BillingBasis(rawValue: billingBasisRaw) ?? .daily,
                    rolloverMode: RolloverMode(rawValue: rolloverModeRaw) ?? .manual,
                    nextRolloverDate: nextRolloverDate,
                    expectedNextIncrement: expectedNextIncrement,
                    subsequentIntervalDays: subsequentIntervalDays,
                    manualRolloverOverride: manualRolloverOverride,
                    includedUsageNotes: includedUsageNotes,
                    accrualStoppedAt: accrualStoppedAt
                )
            }
            set {
                deliveryDate = newValue.deliveryDate
                dailyRate = newValue.rateCard.daily
                weeklyRate = newValue.rateCard.weekly
                fourWeekRate = newValue.rateCard.fourWeek
                billingBasisRaw = newValue.billingBasis.rawValue
                rolloverModeRaw = newValue.rolloverMode.rawValue
                nextRolloverDate = newValue.nextRolloverDate
                expectedNextIncrement = newValue.expectedNextIncrement
                subsequentIntervalDays = newValue.subsequentIntervalDays
                manualRolloverOverride = newValue.manualRolloverOverride
                includedUsageNotes = newValue.includedUsageNotes
                accrualStoppedAt = newValue.accrualStoppedAt
            }
        }

        var sortedEvents: [RentalEventModel] {
            (events ?? []).sorted { $0.timestamp < $1.timestamp }
        }
    }

    // MARK: - Event

    @Model
    final class RentalEventModel {
        var id: UUID = UUID()
        var typeRaw: String = RentalEventType.created.rawValue
        var timestamp: Date = Date()
        var detail: String?
        var contactMethodRaw: String?
        var vendorRepresentative: String?
        var confirmationNumber: String?

        // A single, optional, one-time coordinate. There is no array here and never will be:
        // a list of coordinates is a route, and this app does not keep one.
        var locationLatitude: Double?
        var locationLongitude: Double?
        var locationAccuracyMetres: Double?
        var locationCapturedAt: Date?

        var createdAt: Date = Date()
        var item: RentalItemModel?

        init(
            id: UUID = UUID(),
            type: RentalEventType,
            timestamp: Date,
            detail: String? = nil,
            contactMethod: VendorContactMethod? = nil,
            vendorRepresentative: String? = nil,
            confirmationNumber: String? = nil,
            location: LocationSnapshotRecord? = nil,
            createdAt: Date,
            item: RentalItemModel? = nil
        ) {
            self.id = id
            self.typeRaw = type.rawValue
            self.timestamp = timestamp
            self.detail = detail
            self.contactMethodRaw = contactMethod?.rawValue
            self.vendorRepresentative = vendorRepresentative
            self.confirmationNumber = confirmationNumber
            self.locationLatitude = location?.latitude
            self.locationLongitude = location?.longitude
            self.locationAccuracyMetres = location?.horizontalAccuracyMetres
            self.locationCapturedAt = location?.capturedAt
            self.createdAt = createdAt
            self.item = item
        }

        var type: RentalEventType { RentalEventType(rawValue: typeRaw) ?? .created }

        var contactMethod: VendorContactMethod? {
            contactMethodRaw.flatMap(VendorContactMethod.init(rawValue:))
        }

        var location: LocationSnapshotRecord? {
            guard let locationLatitude, let locationLongitude, let locationCapturedAt else {
                return nil
            }
            return LocationSnapshotRecord(
                latitude: locationLatitude,
                longitude: locationLongitude,
                horizontalAccuracyMetres: locationAccuracyMetres ?? -1,
                capturedAt: locationCapturedAt
            )
        }
    }

    // MARK: - Evidence asset

    @Model
    final class EvidenceAssetModel {
        var id: UUID = UUID()
        /// Relative to the evidence root. Never absolute — iOS reassigns the app container on
        /// restore and on some updates, and an absolute path silently stops resolving.
        var relativePath: String = ""
        var mediaTypeRaw: String = EvidenceMediaType.image.rawValue
        var displayName: String = ""
        var capturedAt: Date = Date()
        var caption: String?
        var sha256: String?
        var thumbnailRelativePath: String?

        var locationLatitude: Double?
        var locationLongitude: Double?
        var locationAccuracyMetres: Double?
        var locationCapturedAt: Date?

        // Exactly one of these is set. SwiftData has no polymorphic relationship, and four
        // optional links with real delete rules beat a loose owner id that nothing cascades from.
        var agreement: RentalAgreementModel?
        var item: RentalItemModel?
        var invoice: VendorInvoiceModel?
        var eventID: UUID?

        init(
            id: UUID = UUID(),
            relativePath: String,
            mediaType: EvidenceMediaType,
            displayName: String,
            capturedAt: Date,
            caption: String? = nil,
            sha256: String? = nil,
            thumbnailRelativePath: String? = nil,
            location: LocationSnapshotRecord? = nil,
            agreement: RentalAgreementModel? = nil,
            item: RentalItemModel? = nil,
            invoice: VendorInvoiceModel? = nil,
            eventID: UUID? = nil
        ) {
            self.id = id
            self.relativePath = relativePath
            self.mediaTypeRaw = mediaType.rawValue
            self.displayName = displayName
            self.capturedAt = capturedAt
            self.caption = caption
            self.sha256 = sha256
            self.thumbnailRelativePath = thumbnailRelativePath
            self.locationLatitude = location?.latitude
            self.locationLongitude = location?.longitude
            self.locationAccuracyMetres = location?.horizontalAccuracyMetres
            self.locationCapturedAt = location?.capturedAt
            self.agreement = agreement
            self.item = item
            self.invoice = invoice
            self.eventID = eventID
        }

        var mediaType: EvidenceMediaType { EvidenceMediaType(rawValue: mediaTypeRaw) ?? .other }

        var location: LocationSnapshotRecord? {
            guard let locationLatitude, let locationLongitude, let locationCapturedAt else {
                return nil
            }
            return LocationSnapshotRecord(
                latitude: locationLatitude,
                longitude: locationLongitude,
                horizontalAccuracyMetres: locationAccuracyMetres ?? -1,
                capturedAt: locationCapturedAt
            )
        }

        var ownerKind: EvidenceOwnerKind {
            if invoice != nil { return .invoice }
            if eventID != nil { return .event }
            if item != nil { return .item }
            return .agreement
        }

        var ownerID: UUID {
            switch ownerKind {
            case .invoice: invoice?.id ?? id
            case .event: eventID ?? id
            case .item: item?.id ?? id
            case .agreement: agreement?.id ?? id
            }
        }
    }

    // MARK: - Invoice

    @Model
    final class VendorInvoiceModel {
        var id: UUID = UUID()
        var invoiceNumber: String?
        var receivedDate: Date = Date()
        var billedThroughDate: Date?
        var invoiceTotal: Decimal = Decimal.zero
        var reviewStatusRaw: String = InvoiceReviewStatus.notReviewed.rawValue
        var notes: String?
        var attachedAt: Date = Date()
        var reviewedAt: Date?
        /// The amount the user says they expect, if they entered one. Overrides the derived
        /// expectation in `InvoiceComparisonEngine`.
        var expectedRentalSubtotalOverride: Decimal?

        var agreement: RentalAgreementModel?
        /// The item this invoice was reviewed against. Optional because an agreement can carry
        /// several items and a vendor invoice sometimes covers all of them.
        var primaryItemID: UUID?

        @Relationship(deleteRule: .cascade, inverse: \InvoiceLineModel.invoice)
        var lines: [InvoiceLineModel]? = []

        @Relationship(deleteRule: .cascade, inverse: \DiscrepancyModel.invoice)
        var discrepancies: [DiscrepancyModel]? = []

        @Relationship(deleteRule: .cascade, inverse: \EvidenceAssetModel.invoice)
        var assets: [EvidenceAssetModel]? = []

        init(
            id: UUID = UUID(),
            invoiceNumber: String? = nil,
            receivedDate: Date,
            billedThroughDate: Date? = nil,
            invoiceTotal: Decimal = .zero,
            reviewStatus: InvoiceReviewStatus = .notReviewed,
            notes: String? = nil,
            attachedAt: Date,
            reviewedAt: Date? = nil,
            expectedRentalSubtotalOverride: Decimal? = nil,
            agreement: RentalAgreementModel? = nil,
            primaryItemID: UUID? = nil
        ) {
            self.id = id
            self.invoiceNumber = invoiceNumber
            self.receivedDate = receivedDate
            self.billedThroughDate = billedThroughDate
            self.invoiceTotal = invoiceTotal
            self.reviewStatusRaw = reviewStatus.rawValue
            self.notes = notes
            self.attachedAt = attachedAt
            self.reviewedAt = reviewedAt
            self.expectedRentalSubtotalOverride = expectedRentalSubtotalOverride
            self.agreement = agreement
            self.primaryItemID = primaryItemID
            self.lines = []
            self.discrepancies = []
            self.assets = []
        }

        var reviewStatus: InvoiceReviewStatus {
            InvoiceReviewStatus(rawValue: reviewStatusRaw) ?? .notReviewed
        }

        var openDiscrepancyCount: Int {
            (discrepancies ?? []).filter { $0.status.isOpen }.count
        }
    }

    @Model
    final class InvoiceLineModel {
        var id: UUID = UUID()
        var categoryRaw: String = InvoiceCategory.other.rawValue
        var detail: String = ""
        var quantity: Decimal?
        var unitPrice: Decimal?
        var amount: Decimal = Decimal.zero
        var appearedInContract: Bool = false
        var reviewStateRaw: String = LineReviewState.unreviewed.rawValue
        var sortIndex: Int = 0

        var invoice: VendorInvoiceModel?

        init(
            id: UUID = UUID(),
            category: InvoiceCategory,
            detail: String = "",
            quantity: Decimal? = nil,
            unitPrice: Decimal? = nil,
            amount: Decimal,
            appearedInContract: Bool = false,
            reviewState: LineReviewState = .unreviewed,
            sortIndex: Int = 0,
            invoice: VendorInvoiceModel? = nil
        ) {
            self.id = id
            self.categoryRaw = category.rawValue
            self.detail = detail
            self.quantity = quantity
            self.unitPrice = unitPrice
            self.amount = amount
            self.appearedInContract = appearedInContract
            self.reviewStateRaw = reviewState.rawValue
            self.sortIndex = sortIndex
            self.invoice = invoice
        }

        var category: InvoiceCategory { InvoiceCategory(rawValue: categoryRaw) ?? .other }
        var reviewState: LineReviewState { LineReviewState(rawValue: reviewStateRaw) ?? .unreviewed }
    }

    // MARK: - Discrepancy

    @Model
    final class DiscrepancyModel {
        var id: UUID = UUID()
        var typeRaw: String = DiscrepancyType.rentalSubtotalDiffers.rawValue
        var lineID: UUID?
        var itemID: UUID?
        var expectedAmount: Decimal?
        var invoicedAmount: Decimal?
        var difference: Decimal?
        var explanation: String = ""
        var statusRaw: String = DiscrepancyStatus.open.rawValue
        var resolutionNotes: String?
        var createdAt: Date = Date()
        var resolvedAt: Date?

        var invoice: VendorInvoiceModel?

        init(
            id: UUID = UUID(),
            type: DiscrepancyType,
            lineID: UUID? = nil,
            itemID: UUID? = nil,
            expectedAmount: Decimal? = nil,
            invoicedAmount: Decimal? = nil,
            difference: Decimal? = nil,
            explanation: String,
            status: DiscrepancyStatus = .open,
            resolutionNotes: String? = nil,
            createdAt: Date,
            resolvedAt: Date? = nil,
            invoice: VendorInvoiceModel? = nil
        ) {
            self.id = id
            self.typeRaw = type.rawValue
            self.lineID = lineID
            self.itemID = itemID
            self.expectedAmount = expectedAmount
            self.invoicedAmount = invoicedAmount
            self.difference = difference
            self.explanation = explanation
            self.statusRaw = status.rawValue
            self.resolutionNotes = resolutionNotes
            self.createdAt = createdAt
            self.resolvedAt = resolvedAt
            self.invoice = invoice
        }

        var type: DiscrepancyType { DiscrepancyType(rawValue: typeRaw) ?? .rentalSubtotalDiffers }
        var status: DiscrepancyStatus { DiscrepancyStatus(rawValue: statusRaw) ?? .open }
    }
}

// Short names for the rest of the app. When SchemaV2 arrives these aliases point at V2 and the
// call sites do not change.
typealias Vendor = OffRentSchemaV1.VendorModel
typealias JobSite = OffRentSchemaV1.JobSiteModel
typealias RentalAgreement = OffRentSchemaV1.RentalAgreementModel
typealias RentalItem = OffRentSchemaV1.RentalItemModel
typealias RentalEvent = OffRentSchemaV1.RentalEventModel
typealias EvidenceAsset = OffRentSchemaV1.EvidenceAssetModel
typealias VendorInvoice = OffRentSchemaV1.VendorInvoiceModel
typealias InvoiceLine = OffRentSchemaV1.InvoiceLineModel
typealias Discrepancy = OffRentSchemaV1.DiscrepancyModel
