import Foundation

/// Translation between the persisted models and the Foundation-only records used by export,
/// import, the evidence packet and the CSV writer.
///
/// Every one of those features works on records rather than on models, which is why they are
/// testable without a `ModelContext` and why a schema change does not ripple into the export
/// format.

extension Vendor {
    var record: VendorRecord {
        VendorRecord(
            id: id, name: name, branch: branch, phone: phone, email: email, link: link,
            standardNotes: standardNotes, contactName: contactName, address: address,
            createdAt: createdAt, modifiedAt: modifiedAt
        )
    }

    convenience init(record: VendorRecord) {
        self.init(
            id: record.id, name: record.name, branch: record.branch, phone: record.phone,
            email: record.email, link: record.link, standardNotes: record.standardNotes,
            contactName: record.contactName, address: record.address,
            createdAt: record.createdAt, modifiedAt: record.modifiedAt
        )
    }
}

extension JobSite {
    var record: JobSiteRecord {
        JobSiteRecord(
            id: id, name: name, projectIdentifier: projectIdentifier, address: address,
            notes: notes, placeName: placeName, latitude: latitude, longitude: longitude,
            createdAt: createdAt, modifiedAt: modifiedAt
        )
    }

    convenience init(record: JobSiteRecord) {
        self.init(
            id: record.id, name: record.name, projectIdentifier: record.projectIdentifier,
            address: record.address, notes: record.notes, placeName: record.placeName,
            latitude: record.latitude, longitude: record.longitude,
            createdAt: record.createdAt, modifiedAt: record.modifiedAt
        )
    }
}

extension RentalAgreement {
    var record: AgreementRecord? {
        guard let vendorID = vendor?.id else { return nil }
        return AgreementRecord(
            id: id, vendorID: vendorID, jobSiteID: jobSite?.id, agreementNumber: agreementNumber,
            purchaseOrderNumber: purchaseOrderNumber,
            startDate: startDate, scheduledEndDate: scheduledEndDate,
            disputeWindowDaysOverride: disputeWindowDaysOverride, notes: notes,
            createdAt: createdAt, modifiedAt: modifiedAt
        )
    }
}

extension RentalItem {
    var record: RentalItemRecord? {
        guard let agreementID = agreement?.id else { return nil }
        return RentalItemRecord(
            id: id, agreementID: agreementID, equipmentName: equipmentName,
            equipmentClass: equipmentClass,
            vendorEquipmentIdentifier: vendorEquipmentIdentifier, serialNumber: serialNumber,
            status: status, terms: terms, meterUnit: meterUnit, notes: notes,
            createdAt: createdAt, modifiedAt: modifiedAt
        )
    }
}

extension RentalEvent {
    var record: RentalEventRecord? {
        guard let itemID = item?.id else { return nil }
        return RentalEventRecord(
            id: id, itemID: itemID, type: type, timestamp: timestamp, detail: detail,
            contactMethod: contactMethod, vendorRepresentative: vendorRepresentative,
            confirmationNumber: confirmationNumber, locationSnapshot: location,
            createdAt: createdAt
        )
    }

    /// The packet's view of one event.
    var timelineEntry: EvidencePacket.TimelineEntry {
        EvidencePacket.TimelineEntry(
            timestamp: timestamp,
            title: type.displayName,
            detail: detail,
            contactMethod: contactMethod,
            vendorRepresentative: vendorRepresentative,
            confirmationNumber: confirmationNumber,
            hasLocation: location != nil
        )
    }
}

extension EvidenceAsset {
    var record: EvidenceAssetRecord {
        EvidenceAssetRecord(
            id: id, ownerKind: ownerKind, ownerID: ownerID, relativePath: relativePath,
            mediaType: mediaType, displayName: displayName, capturedAt: capturedAt,
            coordinate: location, caption: caption, sha256: sha256,
            thumbnailRelativePath: thumbnailRelativePath
        )
    }

    var summary: EvidencePacket.AssetSummary {
        EvidencePacket.AssetSummary(
            displayName: displayName, caption: caption, capturedAt: capturedAt,
            mediaType: mediaType, relativePath: relativePath, sha256: sha256,
            hasCoordinate: location != nil
        )
    }
}

extension InvoiceLine {
    var value: InvoiceLineValue {
        InvoiceLineValue(
            id: id, category: category, detail: detail, quantity: quantity,
            unitPrice: unitPrice, amount: amount, appearedInContract: appearedInContract,
            reviewState: reviewState
        )
    }

    convenience init(value: InvoiceLineValue, sortIndex: Int, invoice: VendorInvoice? = nil) {
        self.init(
            id: value.id, category: value.category, detail: value.detail,
            quantity: value.quantity, unitPrice: value.unitPrice, amount: value.amount,
            appearedInContract: value.appearedInContract, reviewState: value.reviewState,
            sortIndex: sortIndex, invoice: invoice
        )
    }
}

extension VendorInvoice {
    var value: InvoiceValue {
        let stored: [InvoiceLine] = lines ?? []
        let orderedLines: [InvoiceLineValue] = stored
            .sorted { $0.sortIndex < $1.sortIndex }
            .map(\.value)
        return InvoiceValue(
            id: id,
            invoiceNumber: invoiceNumber,
            receivedDate: receivedDate,
            billedThroughDate: billedThroughDate,
            lines: orderedLines,
            invoiceTotal: invoiceTotal,
            reviewStatus: reviewStatus,
            notes: notes
        )
    }

    var record: InvoiceRecord? {
        guard let agreementID = agreement?.id else { return nil }
        return InvoiceRecord(
            id: id, agreementID: agreementID, invoice: value,
            attachmentAssetID: (assets ?? []).first?.id, attachedAt: attachedAt,
            reviewedAt: reviewedAt
        )
    }
}

extension Discrepancy {
    var value: DiscrepancyValue {
        DiscrepancyValue(
            id: id, type: type, lineID: lineID, expectedAmount: expectedAmount,
            invoicedAmount: invoicedAmount, difference: difference, explanation: explanation,
            status: status, createdAt: createdAt, resolvedAt: resolvedAt,
            resolutionNotes: resolutionNotes
        )
    }

    var record: DiscrepancyRecord? {
        guard let invoiceID = invoice?.id else { return nil }
        return DiscrepancyRecord(id: id, invoiceID: invoiceID, itemID: itemID, discrepancy: value)
    }

    convenience init(value: DiscrepancyValue, itemID: UUID?, invoice: VendorInvoice?) {
        self.init(
            id: value.id, type: value.type, lineID: value.lineID, itemID: itemID,
            expectedAmount: value.expectedAmount, invoicedAmount: value.invoicedAmount,
            difference: value.difference, explanation: value.explanation, status: value.status,
            resolutionNotes: value.resolutionNotes, createdAt: value.createdAt,
            resolvedAt: value.resolvedAt, invoice: invoice
        )
    }
}
