import Foundation

/// The hands-on half of the tour: the real workflow, in the real app, one step at a time.
///
/// The step is *derived from the rental's status*, not tracked by counting button presses. That
/// is the whole design. A guide that advances on taps has to be told about every route through
/// the app — the detail screen, a deep link from a notification, an App Intent, an undo — and
/// gets stuck the first time somebody arrives by a path nobody wired up. A guide that reads the
/// state cannot get stuck, cannot skip ahead of itself, and needs no plumbing at all: if the
/// rental is awaiting pickup, the step is "record the pickup", however it got there.
///
/// It also means the guide is a pure function, which is why it lives here and has tests.
enum GuidedTourStep: String, CaseIterable, Sendable {
    case createRental
    case markDone
    case recordConfirmation
    case acknowledgePickup
    case recordPickup
    case awaitInvoice
    case attachInvoice
    case reviewInvoice
    case finished

    /// Steps a person walks through, which excludes the end state.
    static var walkable: [GuidedTourStep] {
        allCases.filter { $0 != .finished }
    }

    var number: Int { (Self.walkable.firstIndex(of: self) ?? 0) + 1 }
    static var count: Int { walkable.count }

    /// What this step is called.
    var title: String {
        switch self {
        case .createRental: "Add a rental"
        case .markDone: "Finish with the machine"
        case .recordConfirmation: "Record the vendor confirmation"
        case .acknowledgePickup: "Awaiting pickup"
        case .recordPickup: "Record the pickup"
        case .awaitInvoice: "Wait for the invoice"
        case .attachInvoice: "Attach the final invoice"
        case .reviewInvoice: "Review this charge"
        case .finished: "That is the whole workflow"
        }
    }

    /// What to do, naming the control the screen actually shows at this point.
    var instruction: String {
        switch self {
        case .createRental:
            "Tap Add rental and put in a machine, the company, and a daily rate. It does not have to be real — you can delete it afterwards."
        case .markDone:
            "Open the rental and tap Mark equipment done. That records that you finished with it. It does not tell the rental company anything."
        case .recordConfirmation:
            "Call the yard, then tap Record vendor confirmation and write down the number they gave you. This is the step that protects you."
        case .acknowledgePickup:
            "The confirmation is saved. Tap Awaiting pickup to say the machine is off rent but still on site."
        case .recordPickup:
            "When the truck collects it, tap Record pickup. Confirmation and pickup are kept apart on purpose — they are different facts."
        case .awaitInvoice:
            "Pickup is recorded. Tap Awaiting invoice while you wait for the rental company to bill you."
        case .attachInvoice:
            "When the invoice arrives, tap Attach final invoice and enter the total and its lines."
        case .reviewInvoice:
            "Compare it against the terms you confirmed. If something does not line up, record a follow-up; if it does, resolve it."
        case .finished:
            "Add a rental, finish with it, record what the yard told you, record the pickup, and check the bill against what you confirmed."
        }
    }

    var symbol: String {
        switch self {
        case .createRental: "plus.circle"
        case .markDone: "checkmark.circle"
        case .recordConfirmation: "phone.badge.waveform"
        case .acknowledgePickup: "clock.badge.checkmark"
        case .recordPickup: "shippingbox.and.arrow.backward"
        case .awaitInvoice: "hourglass"
        case .attachInvoice: "doc.badge.plus"
        case .reviewInvoice: "list.clipboard"
        case .finished: "checkmark.seal"
        }
    }

    /// Whether the guide should stop following this rental and congratulate the user.
    var isFinished: Bool { self == .finished }

    // MARK: - Deriving the step

    /// The step for a rental in this status. `nil` means there is no rental to follow yet.
    ///
    /// Archived counts as finished rather than as a state of its own: somebody who archived the
    /// rental they were practising on has finished with it, and a guide that keeps pointing at
    /// an archived record is a guide nobody can leave.
    static func step(for status: RentalItemStatus?) -> GuidedTourStep {
        guard let status else { return .createRental }
        switch status {
        case .draft, .active: return .markDone
        case .contactVendor: return .recordConfirmation
        case .confirmationRecorded: return .acknowledgePickup
        case .awaitingPickup: return .recordPickup
        case .pickedUp: return .awaitInvoice
        case .awaitingInvoice: return .attachInvoice
        case .invoiceReview, .needsFollowUp: return .reviewInvoice
        case .resolved, .archived: return .finished
        }
    }
}
