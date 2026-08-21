import Foundation

/// What the user is asking to do to a rental item.
///
/// Intents are named for the user's action, not for the destination status, so that adding a
/// status later cannot silently change what an existing call means.
enum TransitionIntent: Sendable, Equatable {
    case activate
    case markEquipmentDone
    case recordVendorConfirmation(ConfirmationEvidence)
    case acknowledgeAwaitingPickup
    case recordPickup(PickupEvidence)
    case beginAwaitingInvoice
    case attachInvoice
    case flagFollowUp(reason: String)
    case resolve(openDiscrepancyCount: Int)
    case archive
    case reopen(to: RentalItemStatus, reason: String)

    var label: String {
        switch self {
        case .activate: "Activate"
        case .markEquipmentDone: "Mark equipment done"
        case .recordVendorConfirmation: "Record vendor confirmation"
        case .acknowledgeAwaitingPickup: "Await pickup"
        case .recordPickup: "Record pickup"
        case .beginAwaitingInvoice: "Await invoice"
        case .attachInvoice: "Attach invoice"
        case .flagFollowUp: "Record follow-up"
        case .resolve: "Resolve"
        case .archive: "Archive"
        case .reopen: "Reopen"
        }
    }
}

/// Why a transition was refused. Every case carries enough to write a useful message; none of
/// them is a generic failure.
enum TransitionRejection: Error, Sendable, Equatable {
    case notAllowed(from: RentalItemStatus, intent: String)
    case confirmationInvalid(ConfirmationValidationFailure)
    case pickupInvalid(PickupValidationFailure)
    case reopenRequiresReason
    case reopenMustMoveBackwards(from: RentalItemStatus, to: RentalItemStatus)
    case reopenTargetNotReachable(RentalItemStatus)
    case followUpRequiresReason
    case cannotResolveWithOpenDiscrepancies(count: Int)

    var message: String {
        switch self {
        case let .notAllowed(from, intent):
            "\"\(intent)\" is not available while this item is \(from.displayName)."
        case let .confirmationInvalid(failure):
            failure.message
        case let .pickupInvalid(failure):
            failure.message
        case .reopenRequiresReason:
            "Enter a reason for reopening this item."
        case let .reopenMustMoveBackwards(from, to):
            "Reopening moves an item back. \(to.displayName) is not before \(from.displayName)."
        case let .reopenTargetNotReachable(status):
            "\(status.displayName) is not a state an item can be reopened into."
        case .followUpRequiresReason:
            "Describe what needs following up."
        case let .cannotResolveWithOpenDiscrepancies(count):
            count == 1
                ? "One possible mismatch is still open. Accept it or record a follow-up first."
                : "\(count) possible mismatches are still open. Accept them or record a follow-up first."
        }
    }
}

/// The status the item lands in, plus the events the caller must append.
///
/// The service never writes anything itself. It computes; the persistence layer applies. That is
/// what makes the whole state machine testable without a database.
struct TransitionOutcome: Sendable, Equatable {
    var resultingStatus: RentalItemStatus
    var events: [RentalEventType]
}

/// The single authority on how a rental item may move.
///
/// There is no other place in the app that assigns `RentalItem.status`. `verify_repository.py`
/// enforces that: any assignment to `.status` outside this file and the workflow service fails
/// the build.
enum StatusTransitionService {

    /// The forward transition table, as data rather than as branches, so the documentation in
    /// `docs/STATUS_TRANSITIONS.md` can be generated from it and cannot drift.
    static let allowedTransitions: [RentalItemStatus: Set<RentalItemStatus>] = [
        .draft:                [.active, .archived],
        .active:               [.contactVendor],
        .contactVendor:        [.confirmationRecorded],
        .confirmationRecorded: [.awaitingPickup],
        .awaitingPickup:       [.pickedUp],
        .pickedUp:             [.awaitingInvoice],
        .awaitingInvoice:      [.invoiceReview],
        .invoiceReview:        [.needsFollowUp, .resolved],
        .needsFollowUp:        [.invoiceReview, .resolved],
        .resolved:             [.archived],
        .archived:             [],
    ]

    /// States an item may be reopened *into*. Reopening into `draft` is not offered: a rental that
    /// happened cannot un-happen, and the timeline would then contradict itself.
    static let reopenTargets: Set<RentalItemStatus> = [
        .active, .contactVendor, .awaitingPickup, .awaitingInvoice, .invoiceReview, .needsFollowUp,
    ]

    static func canTransition(from current: RentalItemStatus, to next: RentalItemStatus) -> Bool {
        allowedTransitions[current]?.contains(next) ?? false
    }

    static func apply(
        _ intent: TransitionIntent,
        to current: RentalItemStatus
    ) -> Result<TransitionOutcome, TransitionRejection> {

        switch intent {

        case .activate:
            return advance(from: current, to: .active, intent: intent, events: [.activated])

        case .markEquipmentDone:
            return advance(
                from: current, to: .contactVendor, intent: intent, events: [.equipmentMarkedDone]
            )

        case let .recordVendorConfirmation(evidence):
            // The order matters. Validate the user's affirmation *before* checking whether the
            // status permits the move, so a user in the wrong state still gets told the real
            // problem rather than a state-machine message.
            if let failure = evidence.validationFailure {
                return .failure(.confirmationInvalid(failure))
            }
            return advance(
                from: current,
                to: .confirmationRecorded,
                intent: intent,
                events: [.vendorConfirmationRecorded]
            )

        case .acknowledgeAwaitingPickup:
            return advance(from: current, to: .awaitingPickup, intent: intent, events: [])

        case let .recordPickup(evidence):
            if let failure = evidence.validationFailure {
                return .failure(.pickupInvalid(failure))
            }
            return advance(
                from: current, to: .pickedUp, intent: intent, events: [.pickupRecorded]
            )

        case .beginAwaitingInvoice:
            return advance(from: current, to: .awaitingInvoice, intent: intent, events: [])

        case .attachInvoice:
            return advance(
                from: current, to: .invoiceReview, intent: intent, events: [.invoiceAttached]
            )

        case let .flagFollowUp(reason):
            guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.followUpRequiresReason)
            }
            return advance(
                from: current, to: .needsFollowUp, intent: intent, events: [.disputeRecorded]
            )

        case let .resolve(openDiscrepancyCount):
            guard openDiscrepancyCount == 0 else {
                return .failure(.cannotResolveWithOpenDiscrepancies(count: openDiscrepancyCount))
            }
            return advance(from: current, to: .resolved, intent: intent, events: [.resolved])

        case .archive:
            return advance(from: current, to: .archived, intent: intent, events: [])

        case let .reopen(target, reason):
            guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.reopenRequiresReason)
            }
            guard reopenTargets.contains(target) else {
                return .failure(.reopenTargetNotReachable(target))
            }
            guard target.order < current.order else {
                return .failure(.reopenMustMoveBackwards(from: current, to: target))
            }
            // Reopen deliberately bypasses `allowedTransitions`. That is the whole point of it
            // being a separate, reason-carrying intent rather than an ordinary edge.
            return .success(TransitionOutcome(resultingStatus: target, events: [.reopened]))
        }
    }

    private static func advance(
        from current: RentalItemStatus,
        to next: RentalItemStatus,
        intent: TransitionIntent,
        events: [RentalEventType]
    ) -> Result<TransitionOutcome, TransitionRejection> {
        guard canTransition(from: current, to: next) else {
            return .failure(.notAllowed(from: current, intent: intent.label))
        }
        return .success(TransitionOutcome(resultingStatus: next, events: events))
    }

    /// The intents worth surfacing as buttons for an item in `current`.
    ///
    /// Placeholder payloads are used for the cases that carry data; the caller replaces them with
    /// real values when the user actually commits. Nothing here can mutate anything.
    static func availableIntents(for current: RentalItemStatus) -> [TransitionIntent] {
        switch current {
        case .draft: [.activate, .archive]
        case .active: [.markEquipmentDone]
        case .contactVendor: [.recordVendorConfirmation(.placeholder)]
        case .confirmationRecorded: [.acknowledgeAwaitingPickup]
        case .awaitingPickup: [.recordPickup(.placeholder)]
        case .pickedUp: [.beginAwaitingInvoice]
        case .awaitingInvoice: [.attachInvoice]
        case .invoiceReview: [.resolve(openDiscrepancyCount: 0), .flagFollowUp(reason: "")]
        case .needsFollowUp: [.resolve(openDiscrepancyCount: 0)]
        case .resolved: [.archive, .reopen(to: .invoiceReview, reason: "")]
        case .archived: [.reopen(to: .invoiceReview, reason: "")]
        }
    }
}

extension ConfirmationEvidence {
    /// Used only to describe the *shape* of an available action in menus. It is invalid on
    /// purpose — `validationFailure` rejects it — so it can never be committed by accident.
    static var placeholder: ConfirmationEvidence {
        ConfirmationEvidence(confirmedAt: Date(timeIntervalSince1970: 0))
    }
}

extension PickupEvidence {
    static var placeholder: PickupEvidence {
        PickupEvidence(pickedUpAt: Date(timeIntervalSince1970: 0))
    }
}
