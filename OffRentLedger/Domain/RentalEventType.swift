import Foundation

/// The append-oriented timeline vocabulary.
///
/// Events are the audit trail that the evidence packet is built from, so they are written for a
/// reader who was not there: every label describes who did what, and none of them implies the app
/// acted on the user's behalf.
enum RentalEventType: String, CaseIterable, Codable, Sendable {
    case created
    case activated
    case equipmentMarkedDone
    case vendorContactAttempted
    case vendorConfirmationRecorded
    case conditionCaptured
    case pickupRecorded
    case invoiceAttached
    case mismatchFlagged
    case mismatchAccepted
    case disputeRecorded
    case evidenceExported
    case resolved
    case reopened

    var displayName: String {
        switch self {
        case .created: "Rental item created"
        case .activated: "Marked active"
        case .equipmentMarkedDone: "Equipment marked done"
        case .vendorContactAttempted: "Contact attempt recorded"
        case .vendorConfirmationRecorded: "Vendor confirmation recorded"
        case .conditionCaptured: "Condition captured"
        case .pickupRecorded: "Pickup recorded"
        case .invoiceAttached: "Invoice attached"
        case .mismatchFlagged: "Possible mismatch flagged"
        case .mismatchAccepted: "Possible mismatch accepted"
        case .disputeRecorded: "Follow-up recorded"
        case .evidenceExported: "Evidence packet exported"
        case .resolved: "Item resolved"
        case .reopened: "Item reopened"
        }
    }

    var symbolName: String {
        switch self {
        case .created: "plus.circle"
        case .activated: "play.circle"
        case .equipmentMarkedDone: "hand.raised"
        case .vendorContactAttempted: "phone.arrow.up.right"
        case .vendorConfirmationRecorded: "checkmark.rectangle.stack"
        case .conditionCaptured: "camera"
        case .pickupRecorded: "truck.box"
        case .invoiceAttached: "paperclip"
        case .mismatchFlagged: "exclamationmark.triangle"
        case .mismatchAccepted: "hand.thumbsup"
        case .disputeRecorded: "flag"
        case .evidenceExported: "square.and.arrow.up"
        case .resolved: "checkmark.seal"
        case .reopened: "arrow.uturn.backward"
        }
    }

    /// Events the user may not edit or delete after the fact, because the evidence packet's value
    /// depends on the timeline being an account of what happened rather than a tidy summary.
    /// The user can always *add* a correcting event, and can delete the whole rental.
    var isImmutable: Bool {
        switch self {
        case .vendorConfirmationRecorded, .pickupRecorded, .evidenceExported, .reopened: true
        default: false
        }
    }
}
