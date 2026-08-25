import Foundation
import OSLog
import SwiftData

/// The only thing in the app that assigns `RentalItem.statusRaw` or appends a `RentalEvent`.
///
/// `scripts/verify_repository.py` fails the build if `statusRaw` is written anywhere else. That
/// single rule is what makes the state machine an actual guarantee instead of a convention: a
/// view cannot decide an item is confirmed, because a view has no way to say so.
///
/// Every method returns a `Result`. Nothing here throws a rejection away or coerces an invalid
/// transition into a valid-looking one.
@MainActor
struct RentalWorkflowService {

    private static let logger = Logger(subsystem: "com.idlery.offrent", category: "workflow")

    let context: ModelContext
    let clock: any Clock

    init(context: ModelContext, clock: any Clock) {
        self.context = context
        self.clock = clock
    }

    // MARK: - Transitions

    @discardableResult
    func apply(
        _ intent: TransitionIntent,
        to item: RentalItem,
        detail: String? = nil,
        location: LocationSnapshotRecord? = nil
    ) -> Result<TransitionOutcome, TransitionRejection> {

        let result = StatusTransitionService.apply(intent, to: item.status)

        guard case let .success(outcome) = result else {
            if case let .failure(rejection) = result {
                // Rejections are expected and are shown to the user; they are logged at info so a
                // support conversation can reconstruct what the app refused, without treating a
                // normal refusal as an error.
                Self.logger.info("Transition refused: \(rejection.message, privacy: .public)")
            }
            return result
        }

        item.statusRaw = outcome.resultingStatus.rawValue
        item.modifiedAt = clock.now

        // Accrual stops the moment the user says the equipment is done, not at pickup. That is
        // the product's central claim about where the money stops, so it lives here rather than
        // in whichever view happened to trigger it.
        switch intent {
        case .markEquipmentDone:
            if item.accrualStoppedAt == nil { item.accrualStoppedAt = clock.now }
        case let .recordVendorConfirmation(evidence):
            // If the vendor confirms off-rent as of an earlier time than the user pressed the
            // button, honour the vendor's time: it is the one on the invoice.
            item.accrualStoppedAt = min(item.accrualStoppedAt ?? evidence.confirmedAt, evidence.confirmedAt)
        case let .reopen(target, _):
            // Reopening into a state that accrues again clears the stop, otherwise the estimate
            // stays frozen while the machine is back on rent.
            if target.accruesRent { item.accrualStoppedAt = nil }
        default:
            break
        }

        for type in outcome.events {
            append(event: type, to: item, intent: intent, detail: detail, location: location)
        }

        refreshEstimate(for: item)
        return result
    }

    /// Records the confirmation and moves straight on to Awaiting Pickup.
    ///
    /// Two transitions, one user action. `Confirmation Recorded` remains a real state in the
    /// machine — a reopen can land on it, and the timeline distinguishes the two events — but a
    /// user who has just got off the phone should not have to press a second button to say the
    /// machine has not been collected yet.
    @discardableResult
    func recordConfirmation(
        _ evidence: ConfirmationEvidence,
        for item: RentalItem,
        location: LocationSnapshotRecord? = nil
    ) -> Result<TransitionOutcome, TransitionRejection> {

        let recorded = apply(
            .recordVendorConfirmation(evidence),
            to: item,
            detail: evidence.notes,
            location: location
        )
        guard case .success = recorded else { return recorded }
        return apply(.acknowledgeAwaitingPickup, to: item)
    }

    /// Records pickup and moves on to Awaiting Invoice, for the same reason.
    @discardableResult
    func recordPickup(
        _ evidence: PickupEvidence,
        for item: RentalItem,
        location: LocationSnapshotRecord? = nil
    ) -> Result<TransitionOutcome, TransitionRejection> {

        let recorded = apply(.recordPickup(evidence), to: item, detail: evidence.notes, location: location)
        guard case .success = recorded else { return recorded }
        return apply(.beginAwaitingInvoice, to: item)
    }

    /// A contact attempt. Deliberately *not* a transition: trying to reach the yard and failing
    /// leaves the item exactly where it was, in Contact Vendor, which is the honest state.
    func recordContactAttempt(
        method: VendorContactMethod,
        representative: String?,
        note: String?,
        for item: RentalItem
    ) {
        append(
            event: .vendorContactAttempted,
            to: item,
            method: method,
            representative: representative,
            detail: note
        )
        item.modifiedAt = clock.now
    }

    // MARK: - Events

    @discardableResult
    func append(
        event type: RentalEventType,
        to item: RentalItem,
        intent: TransitionIntent? = nil,
        method: VendorContactMethod? = nil,
        representative: String? = nil,
        detail: String? = nil,
        location: LocationSnapshotRecord? = nil
    ) -> RentalEvent {

        var contactMethod = method
        var vendorRepresentative = representative
        var confirmationNumber: String?
        var meterReading: Decimal?
        var fuelLevel: FuelLevel?
        var timestamp = clock.now
        var body = detail

        // The confirmation event carries the vendor's own details, and its timestamp is when the
        // user says the vendor confirmed — not when they got around to typing it in.
        if case let .recordVendorConfirmation(evidence) = intent {
            contactMethod = evidence.contactMethod
            vendorRepresentative = evidence.vendorRepresentative
            confirmationNumber = evidence.trimmedConfirmationNumber
            meterReading = evidence.meterReading
            fuelLevel = evidence.fuelLevel
            timestamp = evidence.confirmedAt
            if confirmationNumber == nil, evidence.acknowledgedNoConfirmationNumber {
                body = [body, "User recorded that the vendor gave no confirmation number."]
                    .compactMap { $0 }.joined(separator: "\n")
            }
        }
        if case let .recordPickup(evidence) = intent {
            meterReading = evidence.finalMeterReading
            fuelLevel = evidence.finalFuelLevel
            timestamp = evidence.pickedUpAt
            if let observer = evidence.observedBy, !observer.isEmpty {
                body = [body, "Pickup observed by \(observer)."].compactMap { $0 }.joined(separator: "\n")
            }
        }
        if case let .reopen(target, reason) = intent {
            body = "Reopened to \(target.displayName). Reason: \(reason)"
        }
        if case let .flagFollowUp(reason) = intent {
            body = reason
        }

        let event = RentalEvent(
            type: type,
            timestamp: timestamp,
            detail: body?.isEmpty == true ? nil : body,
            contactMethod: contactMethod,
            vendorRepresentative: vendorRepresentative,
            confirmationNumber: confirmationNumber,
            meterReading: meterReading,
            fuelLevel: fuelLevel,
            location: location,
            createdAt: clock.now,
            item: item
        )
        context.insert(event)
        return event
    }

    // MARK: - Estimate cache

    /// Recomputes the cached estimate for one item.
    ///
    /// The cache exists so a list of a thousand rentals does not run the rate engine once per row
    /// per frame. `RentalRateEngine` remains the authority; nothing reads the cache to make a
    /// decision, only to draw a number that is refreshed on every mutation and on foreground.
    func refreshEstimate(for item: RentalItem) {
        let estimate = RentalRateEngine.estimate(
            terms: item.terms, asOf: clock.now, calendar: clock.calendar
        )
        item.cachedEstimatedRunningCost = estimate.isComplete ? estimate.estimatedTotal : nil
        item.cachedEstimateIsComplete = estimate.isComplete
        item.cachedEstimateAsOf = clock.now
    }

    func refreshEstimates(for items: [RentalItem]) {
        for item in items { refreshEstimate(for: item) }
    }

    // MARK: - Creation

    /// Creates an item in `.draft` and immediately activates it, writing both events.
    ///
    /// Free-tier enforcement happens in the caller, before this is reached, so that the block is
    /// reported with a paywall rather than as a failed save.
    /// `@discardableResult`: the tests assert on the item they get back, the add-rental screen
    /// only needs it to have been written.
    @discardableResult
    func createItem(
        equipmentName: String,
        equipmentClass: String?,
        vendorEquipmentIdentifier: String?,
        serialNumber: String?,
        terms: RentalTerms,
        meterUnit: MeterUnit,
        notes: String?,
        in agreement: RentalAgreement,
        activate: Bool = true
    ) -> RentalItem {
        let item = RentalItem(
            equipmentName: equipmentName,
            equipmentClass: equipmentClass,
            vendorEquipmentIdentifier: vendorEquipmentIdentifier,
            serialNumber: serialNumber,
            status: .draft,
            terms: terms,
            meterUnit: meterUnit,
            notes: notes,
            createdAt: clock.now,
            modifiedAt: clock.now,
            agreement: agreement
        )
        context.insert(item)
        append(event: .created, to: item)
        if activate { apply(.activate, to: item) } else { refreshEstimate(for: item) }
        return item
    }
}
