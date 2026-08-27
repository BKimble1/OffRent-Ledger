import Foundation

enum SubscriptionTier: String, Codable, Sendable {
    case free
    case pro
}

/// Why Pro is or is not active right now. Derived only from StoreKit-verified transactions; the
/// app never writes this from its own state.
enum EntitlementReason: String, Codable, Sendable {
    case noSubscription
    case active
    case expired
    case revoked
    case inBillingRetry
    /// Offline, honouring the last entitlement that was verified. Pro stays on: punishing a user
    /// on a jobsite with no signal for the network's failure is the wrong trade.
    case usingLastVerified

    var displayName: String {
        switch self {
        case .noSubscription: "Not subscribed"
        case .active: "Active"
        case .expired: "Expired"
        case .revoked: "Refunded or revoked"
        case .inBillingRetry: "Billing issue — retrying"
        case .usingLastVerified: "Active (offline)"
        }
    }
}

struct EntitlementState: Codable, Sendable, Equatable {
    var tier: SubscriptionTier
    var reason: EntitlementReason
    /// Only ever set from a value StoreKit actually provided. The app never computes a renewal
    /// date of its own, because a wrong one shown next to a real charge is indefensible.
    var renewalOrExpirationDate: Date?
    var productIdentifier: String?
    var lastVerifiedAt: Date?

    init(
        tier: SubscriptionTier = .free,
        reason: EntitlementReason = .noSubscription,
        renewalOrExpirationDate: Date? = nil,
        productIdentifier: String? = nil,
        lastVerifiedAt: Date? = nil
    ) {
        self.tier = tier
        self.reason = reason
        self.renewalOrExpirationDate = renewalOrExpirationDate
        self.productIdentifier = productIdentifier
        self.lastVerifiedAt = lastVerifiedAt
    }

    static let free = EntitlementState()

    static func pro(
        reason: EntitlementReason = .active,
        renewalOrExpirationDate: Date? = nil,
        productIdentifier: String? = nil,
        lastVerifiedAt: Date? = nil
    ) -> EntitlementState {
        EntitlementState(
            tier: .pro,
            reason: reason,
            renewalOrExpirationDate: renewalOrExpirationDate,
            productIdentifier: productIdentifier,
            lastVerifiedAt: lastVerifiedAt
        )
    }

    var isPro: Bool { tier == .pro }
}

enum ProFeature: String, CaseIterable, Sendable {
    case unlimitedOpenItems
    case invoiceAudit
    case evidencePDFExport
    case advancedReminders
    case fullHistoryExport

    // The Home Screen widget was once a case here. It is not a Pro feature any more: it only
    // shows rentals the user already recorded, and the rule below is that entitlement gates
    // creating records and never seeing them. See `RootView.publishSnapshot`.

    var displayName: String {
        switch self {
        case .unlimitedOpenItems: "Unlimited open rentals"
        case .invoiceAudit: "Invoice audit"
        case .evidencePDFExport: "Evidence packet PDF"
        case .advancedReminders: "Advanced reminders"
        case .fullHistoryExport: "Complete history export"
        }
    }

    var explanation: String {
        switch self {
        case .unlimitedOpenItems:
            "Track as many open rentals at once as you have on the ground."
        case .invoiceAudit:
            "Compare a final invoice against the terms you confirmed, line by line."
        case .evidencePDFExport:
            "Assemble one PDF with the timeline, confirmation number, photos and invoice summary."
        case .advancedReminders:
            "Reminders for rate changes, pickup, invoice review and your dispute window."
        case .fullHistoryExport:
            "Export every rental as CSV and as a structured backup file."
        }
    }
}

enum EntitlementBlock: Error, Sendable, Equatable {
    case openItemLimitReached(limit: Int, current: Int)
    case featureRequiresPro(ProFeature)

    var message: String {
        switch self {
        case let .openItemLimitReached(limit, _):
            limit == 1
                ? "The free plan tracks one open rental at a time. Resolve or archive the one you have, or subscribe to Pro for unlimited open rentals."
                : "The free plan tracks \(limit) open rentals at a time. Resolve or archive one, or subscribe to Pro."
        case let .featureRequiresPro(feature):
            "\(feature.displayName) is part of \(SharedBranding.displayName) Pro."
        }
    }
}

/// What the free plan allows.
///
/// The governing rule, and the one the tests protect hardest: **entitlement gates creation, never
/// access.** A user whose subscription lapses keeps every record, keeps editing them, keeps
/// resolving them, keeps deleting them and keeps exporting the plain formats. Losing Pro means
/// one thing — no *additional* open rental beyond the free limit. Anything else would be holding
/// a contractor's own evidence hostage.
enum EntitlementPolicy {

    static let freeOpenItemLimit = 1

    static func canCreateOpenItem(
        currentOpenCount: Int,
        entitlement: EntitlementState
    ) -> Result<Void, EntitlementBlock> {
        if entitlement.isPro { return .success(()) }
        guard currentOpenCount < freeOpenItemLimit else {
            return .failure(
                .openItemLimitReached(limit: freeOpenItemLimit, current: currentOpenCount)
            )
        }
        return .success(())
    }

    static func isAllowed(_ feature: ProFeature, entitlement: EntitlementState) -> Bool {
        entitlement.isPro
    }

    static func require(
        _ feature: ProFeature,
        entitlement: EntitlementState
    ) -> Result<Void, EntitlementBlock> {
        isAllowed(feature, entitlement: entitlement)
            ? .success(())
            : .failure(.featureRequiresPro(feature))
    }

    // MARK: - Guarantees that hold at every tier
    //
    // These are functions rather than comments so that a future change which breaks one of them
    // breaks a test instead of a customer.

    static func canViewExistingRecords(entitlement: EntitlementState) -> Bool { true }
    static func canEditExistingRecords(entitlement: EntitlementState) -> Bool { true }
    static func canResolveExistingRecords(entitlement: EntitlementState) -> Bool { true }
    static func canDeleteExistingRecords(entitlement: EntitlementState) -> Bool { true }
    /// Deleting all data must never require a subscription. A user leaving the product has to be
    /// able to take their data out and wipe it.
    static func canDeleteAllData(entitlement: EntitlementState) -> Bool { true }
    /// The plain per-rental CSV and the structured backup are not Pro features. Only the
    /// *complete history* export and the assembled PDF are.
    static func canExportSingleRentalCSV(entitlement: EntitlementState) -> Bool { true }
    static func canExportBackup(entitlement: EntitlementState) -> Bool { true }

    /// Items that count against the free limit.
    static func openItemCount(statuses: [RentalItemStatus]) -> Int {
        statuses.filter(\.isOpen).count
    }
}
