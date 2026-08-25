import Foundation

/// Where a single piece of rented equipment sits in the OffRent Ledger workflow.
///
/// The vocabulary is rental-specific on purpose. None of these names is borrowed from another
/// product's workflow, and none of them claims an action the app did not take: `contactVendor`
/// is an instruction to the *user*, and `confirmationRecorded` describes what the user wrote
/// down, not what the vendor did.
enum RentalItemStatus: String, CaseIterable, Codable, Sendable {
    case draft
    case active
    case contactVendor
    case confirmationRecorded
    case awaitingPickup
    case pickedUp
    case awaitingInvoice
    case invoiceReview
    case needsFollowUp
    case resolved
    case archived

    /// Display order, and the ordering used to decide whether a reopen actually moves backwards.
    var order: Int {
        switch self {
        case .draft: 0
        case .active: 1
        case .contactVendor: 2
        case .confirmationRecorded: 3
        case .awaitingPickup: 4
        case .pickedUp: 5
        case .awaitingInvoice: 6
        case .invoiceReview: 7
        case .needsFollowUp: 8
        case .resolved: 9
        case .archived: 10
        }
    }

    var displayName: String {
        switch self {
        case .draft: "Draft"
        case .active: "Active"
        case .contactVendor: "Contact Vendor"
        case .confirmationRecorded: "Confirmation Recorded"
        case .awaitingPickup: "Awaiting Pickup"
        case .pickedUp: "Picked Up"
        case .awaitingInvoice: "Awaiting Invoice"
        case .invoiceReview: "Invoice Review"
        case .needsFollowUp: "Needs Follow-Up"
        case .resolved: "Resolved"
        case .archived: "Archived"
        }
    }

    /// The same state, short enough to sit in a list row beside a note and an amount.
    ///
    /// Added because "Confirmation Recorded" is 21 characters: at 393pt it took a third of the
    /// row and pushed the equipment name onto a second line. Never used on its own — the full
    /// `displayName` remains the accessibility label and the detail-screen wording, so nothing
    /// is only ever described by the abbreviation.
    var shortName: String {
        switch self {
        case .draft: "Draft"
        case .active: "Active"
        case .contactVendor: "To call"
        case .confirmationRecorded: "Confirmed"
        case .awaitingPickup: "Pickup due"
        case .pickedUp: "Picked up"
        case .awaitingInvoice: "Invoice due"
        case .invoiceReview: "Review"
        case .needsFollowUp: "Follow-up"
        case .resolved: "Resolved"
        case .archived: "Archived"
        }
    }

    /// A one-line explanation of what the user is waiting on. Used as the VoiceOver hint and as
    /// the subtitle in list rows, so status is never conveyed by colour alone.
    var explanation: String {
        switch self {
        case .draft:
            "Not started yet. Nothing is being estimated for this item."
        case .active:
            "On the jobsite. Estimated rent is running."
        case .contactVendor:
            "You marked this done. Contact the rental company and get its confirmation number."
        case .confirmationRecorded:
            "You recorded the vendor's confirmation. Next, watch for pickup."
        case .awaitingPickup:
            "Waiting for the rental company to collect the equipment."
        case .pickedUp:
            "You recorded pickup. Next, watch for the final invoice."
        case .awaitingInvoice:
            "Waiting for the vendor's final invoice."
        case .invoiceReview:
            "An invoice is attached and ready for you to review."
        case .needsFollowUp:
            "You recorded something to follow up on with the vendor."
        case .resolved:
            // Describes the record, not an act at the yard. Closing a rental out is something a
            // contractor does with a rental company, and this app never speaks to one; what
            // happened here is that the user finished reviewing the item and their own record
            // moved on. The banned-phrase list held the exact wording and missed this by a
            // single inserted word, which is how a list of literals always fails — so the check
            // matches the shape now, and skips a sentence that denies it.
            "You finished with this item in your records."
        case .archived:
            "Filed away. Still fully readable and exportable."
        }
    }

    /// SF Symbol. Paired with `displayName` everywhere it is drawn — the symbol is decorative
    /// reinforcement, never the only carrier of meaning.
    var symbolName: String {
        switch self {
        case .draft: "square.dashed"
        case .active: "clock.badge.exclamationmark"
        case .contactVendor: "phone.badge.waveform"
        case .confirmationRecorded: "checkmark.rectangle.stack"
        case .awaitingPickup: "truck.box"
        case .pickedUp: "shippingbox.and.arrow.backward"
        case .awaitingInvoice: "doc.text.magnifyingglass"
        case .invoiceReview: "list.clipboard"
        case .needsFollowUp: "exclamationmark.bubble"
        case .resolved: "checkmark.seal"
        case .archived: "archivebox"
        }
    }

    /// True while the item still needs something from the user.
    ///
    /// This is the definition the free-tier limit counts, and it is deliberately generous: an item
    /// stops being "open" as soon as the user resolves or archives it, so a free user who works
    /// tidily is never blocked.
    var isOpen: Bool {
        switch self {
        case .resolved, .archived: false
        default: true
        }
    }

    /// True while the app should keep accruing an estimate for this item.
    var accruesRent: Bool {
        switch self {
        case .active, .contactVendor: true
        default: false
        }
    }

    /// True when the item belongs in the Today action queue.
    var needsAttention: Bool {
        switch self {
        case .contactVendor, .awaitingPickup, .invoiceReview, .needsFollowUp: true
        default: false
        }
    }

    static var activeSection: [RentalItemStatus] {
        allCases.filter { $0 != .resolved && $0 != .archived && $0 != .draft }
    }
}
