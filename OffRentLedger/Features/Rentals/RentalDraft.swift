import Foundation
import Observation
import SwiftData

/// Everything a rental form holds, in one place, so that creating and editing are the same form.
///
/// Before this there were two: `AddRentalView` with eight sections of `@State`, and an
/// `EditRentalItemView` that could reach four of them. So a rental created with the wrong company
/// could not be given the right one, a jobsite could not be added afterwards, and an agreement
/// number typed into the wrong field was permanent. §9 of the brief is that gap; a shared draft
/// is what closes it, because there is then only one definition of what a rental's fields are.
///
/// A class rather than a struct: it is passed to a form and to nested editors, all of which need
/// to see the same object, and `@Observable` gives per-property invalidation without the form
/// redrawing on every keystroke in an unrelated field.
@MainActor
@Observable
final class RentalDraft {

    // Company and jobsite, as identifiers rather than as objects. A draft that held a `Vendor`
    // would keep a live model object alive across a sheet dismissal; an id is resolved when
    // needed and cannot go stale in a way that crashes.
    var companyID: UUID?
    var jobSiteID: UUID?

    // Agreement
    var agreementNumber = ""
    var purchaseOrderNumber = ""
    var deliveryDate = Date()
    var scheduledEndDate: Date?

    // Equipment
    var equipmentName = ""
    var equipmentClass = ""
    var vendorEquipmentIdentifier = ""
    var serialNumber = ""
    var meterUnit: MeterUnit = .hours

    // Terms
    var dailyRate: Decimal?
    var weeklyRate: Decimal?
    var fourWeekRate: Decimal?
    var billingBasis: BillingBasis = .daily
    var rolloverMode: RolloverMode = .manual
    var nextRolloverDate: Date?
    var expectedNextIncrement: Decimal?
    var includedUsageNotes = ""
    var notes = ""

    /// Whether the secondary identifiers section is open. Progressive disclosure: the brief asks
    /// for equipment, scan, company, jobsite, dates and rates first, with the rest available but
    /// not dominating — and a form that opens with eleven fields is one nobody finishes.
    var showsMoreDetails = false

    init(now: Date = Date()) {
        deliveryDate = now
    }

    // MARK: - Loading an existing rental

    /// Fills the draft from a saved rental. Everything a user typed, nothing derived.
    func load(from item: RentalItem) {
        let agreement = item.agreement
        companyID = agreement?.vendor?.id
        jobSiteID = agreement?.jobSite?.id
        agreementNumber = agreement?.agreementNumber ?? ""
        purchaseOrderNumber = agreement?.purchaseOrderNumber ?? ""
        deliveryDate = item.deliveryDate
        scheduledEndDate = agreement?.scheduledEndDate

        equipmentName = item.equipmentName
        equipmentClass = item.equipmentClass ?? ""
        vendorEquipmentIdentifier = item.vendorEquipmentIdentifier ?? ""
        serialNumber = item.serialNumber ?? ""
        meterUnit = item.meterUnit

        let terms = item.terms
        dailyRate = terms.rateCard.daily
        weeklyRate = terms.rateCard.weekly
        fourWeekRate = terms.rateCard.fourWeek
        billingBasis = terms.billingBasis
        rolloverMode = terms.rolloverMode
        nextRolloverDate = terms.nextRolloverDate
        expectedNextIncrement = terms.expectedNextIncrement
        includedUsageNotes = terms.includedUsageNotes ?? ""
        notes = item.notes ?? ""

        // Opened when there is something in it, so an edit does not hide the value it is meant
        // to let somebody correct. The agreement number counts: it is inside the disclosure too,
        // and a rental that has one and nothing else would have opened with it hidden.
        showsMoreDetails = !vendorEquipmentIdentifier.isEmpty || !serialNumber.isEmpty
            || !purchaseOrderNumber.isEmpty || !agreementNumber.isEmpty
    }

    // MARK: - What it produces

    /// The terms, built from the fields.
    ///
    /// `accrualStoppedAt` is deliberately absent: it is set by the workflow service when the user
    /// marks equipment done, and an edit to a rate must not resurrect a rental that has stopped
    /// accruing. `apply(to:)` preserves it.
    func terms(preserving existing: RentalTerms? = nil) -> RentalTerms {
        RentalTerms(
            deliveryDate: deliveryDate,
            rateCard: RateCard(daily: dailyRate, weekly: weeklyRate, fourWeek: fourWeekRate),
            billingBasis: billingBasis,
            rolloverMode: rolloverMode,
            nextRolloverDate: nextRolloverDate,
            expectedNextIncrement: expectedNextIncrement,
            subsequentIntervalDays: existing?.subsequentIntervalDays,
            manualRolloverOverride: existing?.manualRolloverOverride ?? false,
            includedUsageNotes: includedUsageNotes.nilIfBlank,
            accrualStoppedAt: existing?.accrualStoppedAt
        )
    }

    var trimmedEquipmentName: String {
        equipmentName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Validation

    /// What is still missing, named exactly. `nil` when the form can be saved.
    ///
    /// A disabled Save with no explanation is the thing this exists to prevent: on a form this
    /// long the missing field is usually off screen, and "Save" being grey says nothing about
    /// which one.
    var missingRequirement: String? {
        let hasEquipment = !trimmedEquipmentName.isEmpty
        let hasCompany = companyID != nil
        switch (hasEquipment, hasCompany) {
        case (true, true): return nil
        case (false, true): return "Add the equipment name to save."
        case (true, false): return "Choose the rental company to save."
        case (false, false): return "Add the equipment name and choose the rental company to save."
        }
    }

    var canSave: Bool { missingRequirement == nil }

    // MARK: - Scanning

    /// Applies the values the user ticked in the review sheet. Fields the user did not tick are
    /// left exactly as they were.
    func apply(scanned values: [SuggestedField: SuggestedValue]) {
        for (field, value) in values {
            switch (field, value) {
            case let (.purchaseOrderNumber, .text(text)):
                purchaseOrderNumber = text
                showsMoreDetails = true
            case let (.agreementNumber, .text(text)):
                agreementNumber = text
                // Opened, like the other two identifiers. A value applied into a collapsed
                // section is a value the user cannot check, and checking is the entire point
                // of the review screen it just came through.
                showsMoreDetails = true
            case let (.equipmentName, .text(text)): equipmentName = text
            case let (.equipmentIdentifier, .text(text)):
                vendorEquipmentIdentifier = text
                showsMoreDetails = true
            case let (.serialNumber, .text(text)):
                serialNumber = text
                showsMoreDetails = true
            case let (.startDate, .date(date)): deliveryDate = date
            case let (.scheduledEndDate, .date(date)): scheduledEndDate = date
            case let (.dailyRate, .money(amount)): dailyRate = amount
            case let (.weeklyRate, .money(amount)): weeklyRate = amount
            case let (.fourWeekRate, .money(amount)): fourWeekRate = amount
            // The company is deliberately *not* set from a scan. A vendor name read off a
            // letterhead is a string; the draft needs a reusable record, and silently creating
            // one from OCR is how the duplicate companies in the screenshots happened. The
            // scanned name is surfaced separately as a suggestion for the picker's search.
            default: break
            }
        }
    }

    /// A company name a scan proposed, so the picker can be opened pre-searched rather than the
    /// app inventing a record nobody chose.
    var scannedCompanyName: String?

    func noteScannedCompany(_ values: [SuggestedField: SuggestedValue]) {
        if case let .text(name)? = values[.vendorName] { scannedCompanyName = name }
    }
}
