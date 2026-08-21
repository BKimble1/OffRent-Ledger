import Foundation

/// What the user tells the app after they contacted the rental company.
///
/// `userAffirmedContact` is the load-bearing field. The app has no way to observe a phone call, so
/// the only honest basis for moving an item out of `contactVendor` is the user explicitly saying
/// they made contact. `StatusTransitionService` refuses the transition without it, and that
/// refusal is what stops the workflow from ever implying the app did the calling.
struct ConfirmationEvidence: Codable, Sendable, Equatable {
    var confirmationNumber: String?
    var vendorRepresentative: String?
    var contactMethod: VendorContactMethod
    var confirmedAt: Date
    var notes: String?

    /// Set only by the user ticking the affirmation control on the confirmation sheet.
    var userAffirmedContact: Bool

    /// The escape hatch for a vendor that does not issue confirmation numbers. The user has to say
    /// so deliberately; the app will not simply accept a blank field.
    var acknowledgedNoConfirmationNumber: Bool

    var meterReading: Decimal?
    var fuelLevel: FuelLevel?

    init(
        confirmationNumber: String? = nil,
        vendorRepresentative: String? = nil,
        contactMethod: VendorContactMethod = .phone,
        confirmedAt: Date,
        notes: String? = nil,
        userAffirmedContact: Bool = false,
        acknowledgedNoConfirmationNumber: Bool = false,
        meterReading: Decimal? = nil,
        fuelLevel: FuelLevel? = nil
    ) {
        self.confirmationNumber = confirmationNumber
        self.vendorRepresentative = vendorRepresentative
        self.contactMethod = contactMethod
        self.confirmedAt = confirmedAt
        self.notes = notes
        self.userAffirmedContact = userAffirmedContact
        self.acknowledgedNoConfirmationNumber = acknowledgedNoConfirmationNumber
        self.meterReading = meterReading
        self.fuelLevel = fuelLevel
    }

    var trimmedConfirmationNumber: String? {
        guard let confirmationNumber else { return nil }
        let trimmed = confirmationNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var hasConfirmationNumber: Bool { trimmedConfirmationNumber != nil }

    /// Everything the transition needs, checked in one place so the sheet's Save button and the
    /// state machine cannot disagree about what "complete" means.
    var validationFailure: ConfirmationValidationFailure? {
        if !userAffirmedContact { return .contactNotAffirmed }
        if !hasConfirmationNumber && !acknowledgedNoConfirmationNumber {
            return .missingConfirmationNumber
        }
        if let meterReading, MoneyMath.isNegative(meterReading) { return .negativeMeterReading }
        return nil
    }

    var isValid: Bool { validationFailure == nil }
}

enum ConfirmationValidationFailure: String, Codable, Sendable, Equatable {
    case contactNotAffirmed
    case missingConfirmationNumber
    case negativeMeterReading

    var message: String {
        switch self {
        case .contactNotAffirmed:
            "Confirm that you contacted the rental company before recording this."
        case .missingConfirmationNumber:
            "Enter the vendor's confirmation number, or tick \"Vendor did not give a number\"."
        case .negativeMeterReading:
            "A meter reading cannot be negative."
        }
    }
}

/// What the user records when the equipment actually leaves.
struct PickupEvidence: Codable, Sendable, Equatable {
    var pickedUpAt: Date
    var observedBy: String?
    var finalMeterReading: Decimal?
    var finalFuelLevel: FuelLevel?
    var notes: String?

    init(
        pickedUpAt: Date,
        observedBy: String? = nil,
        finalMeterReading: Decimal? = nil,
        finalFuelLevel: FuelLevel? = nil,
        notes: String? = nil
    ) {
        self.pickedUpAt = pickedUpAt
        self.observedBy = observedBy
        self.finalMeterReading = finalMeterReading
        self.finalFuelLevel = finalFuelLevel
        self.notes = notes
    }

    var validationFailure: PickupValidationFailure? {
        if let finalMeterReading, MoneyMath.isNegative(finalMeterReading) {
            return .negativeMeterReading
        }
        return nil
    }

    var isValid: Bool { validationFailure == nil }
}

enum PickupValidationFailure: String, Codable, Sendable, Equatable {
    case negativeMeterReading

    var message: String {
        switch self {
        case .negativeMeterReading: "A meter reading cannot be negative."
        }
    }
}
