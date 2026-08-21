import Foundation
import OSLog
import StoreKit

/// What the paywall and the entitlement checks talk to.
@MainActor
protocol SubscriptionProviding: AnyObject, Observable {
    var entitlement: EntitlementState { get }
    var products: [SubscriptionProduct] { get }
    var isLoadingProducts: Bool { get }
    var lastError: SubscriptionError? { get }

    func loadProducts() async
    func purchase(_ product: SubscriptionProduct) async -> PurchaseResult
    func restore() async
    func refreshEntitlement() async
    func startObservingTransactions()
}

/// A product as the UI needs it.
///
/// `displayPrice` is StoreKit's own localised string. The app never formats a price itself and
/// never stores one — a hardcoded "$14.99" is wrong the day a price changes, wrong in every other
/// storefront, and it is the kind of wrong that ends up in an App Review rejection.
struct SubscriptionProduct: Identifiable, Sendable, Equatable {
    var id: String
    var displayName: String
    var description: String
    var displayPrice: String
    var period: SubscriptionPeriod
    /// Price per month, localised, for the annual option. Shown as information, never as a
    /// countdown or a pressure device.
    var monthlyEquivalentPrice: String?
    var isAnnual: Bool { period == .year }
}

enum SubscriptionPeriod: Sendable, Equatable {
    case month
    case year
    case other

    var displayName: String {
        switch self {
        case .month: "Monthly"
        case .year: "Annual"
        case .other: "Subscription"
        }
    }

    var renewalDescription: String {
        switch self {
        case .month: "Renews every month until cancelled."
        case .year: "Renews every year until cancelled."
        case .other: "Renews until cancelled."
        }
    }
}

enum PurchaseResult: Sendable, Equatable {
    case purchased
    case pending
    case cancelled
    case failed(SubscriptionError)
}

enum SubscriptionError: Error, Sendable, Equatable {
    case productsUnavailable
    case purchaseFailed(String)
    case verificationFailed
    case notAllowed

    var message: String {
        switch self {
        case .productsUnavailable:
            "Subscription options could not be loaded. Check your connection and try again."
        case let .purchaseFailed(detail):
            "The purchase did not complete. \(detail)"
        case .verificationFailed:
            "The App Store could not verify that purchase. Nothing was unlocked. Try Restore Purchases."
        case .notAllowed:
            "Purchases are not allowed on this device."
        }
    }
}

/// StoreKit 2.
///
/// Three rules run through this file:
///
/// 1. **Only verified transactions count.** `VerificationResult.unverified` is ignored entirely
///    rather than trusted-with-a-warning. An unverified transaction is what a jailbreak receipt
///    injector produces.
/// 2. **No date is ever invented.** `renewalOrExpirationDate` is set only from a value StoreKit
///    actually supplied. If StoreKit does not know when a subscription renews, the app says
///    nothing rather than guessing — a wrong renewal date shown next to a real charge is
///    indefensible.
/// 3. **Offline keeps the last verified entitlement.** A contractor in a basement with no signal
///    does not lose the features they paid for.
@MainActor
@Observable
final class StoreKitSubscriptionService: SubscriptionProviding {

    private static let logger = Logger(subsystem: "com.idlery.offrent", category: "storekit")

    private(set) var entitlement: EntitlementState = .free
    private(set) var products: [SubscriptionProduct] = []
    private(set) var isLoadingProducts = false
    private(set) var lastError: SubscriptionError?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var storeProducts: [String: Product] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clock: any Clock

    private static let cachedEntitlementKey = "com.idlery.offrent.lastVerifiedEntitlement"

    init(clock: any Clock, defaults: UserDefaults = .standard) {
        self.clock = clock
        self.defaults = defaults
        self.entitlement = Self.loadCachedEntitlement(from: defaults) ?? .free
    }

    deinit { updatesTask?.cancel() }

    // MARK: - Lifecycle

    func startObservingTransactions() {
        guard updatesTask == nil else { return }
        // Started at launch and never cancelled while the app lives. A transaction that completes
        // outside the app — an Ask-to-Buy approval, a renewal, a refund — arrives here, and a
        // listener that only ran during the paywall would miss all three.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if case let .verified(transaction) = update {
                    await transaction.finish()
                    await self.refreshEntitlement()
                } else {
                    Self.logger.error("Ignoring an unverified transaction update")
                }
            }
        }
    }

    // MARK: - Products

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: AppConfiguration.subscriptionProductIdentifiers)
            storeProducts = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
            products = loaded
                .map(Self.describe)
                // Monthly first, annual second. The annual option is marked as better value; it
                // is not preselected and there is no timer next to it.
                .sorted { lhs, rhs in lhs.isAnnual == rhs.isAnnual ? lhs.id < rhs.id : !lhs.isAnnual }
            lastError = products.isEmpty ? .productsUnavailable : nil
        } catch {
            Self.logger.error("Product load failed: \(String(describing: error), privacy: .public)")
            lastError = .productsUnavailable
        }
    }

    private static func describe(_ product: Product) -> SubscriptionProduct {
        var period = SubscriptionPeriod.other
        var monthlyEquivalent: String?

        if let subscription = product.subscription {
            switch subscription.subscriptionPeriod.unit {
            case .month where subscription.subscriptionPeriod.value == 1: period = .month
            case .year where subscription.subscriptionPeriod.value == 1: period = .year
            default: period = .other
            }
            if period == .year {
                // Formatted through the product's own currency and locale, from its own Decimal
                // price. Twelve is exact here; there is no floating-point division.
                let perMonth = product.price / Decimal(12)
                monthlyEquivalent = perMonth.formatted(
                    .currency(code: product.priceFormatStyle.currencyCode)
                        .precision(.fractionLength(2))
                )
            }
        }

        return SubscriptionProduct(
            id: product.id,
            displayName: product.displayName,
            description: product.description,
            displayPrice: product.displayPrice,
            period: period,
            monthlyEquivalentPrice: monthlyEquivalent
        )
    }

    // MARK: - Purchasing

    func purchase(_ product: SubscriptionProduct) async -> PurchaseResult {
        guard let storeProduct = storeProducts[product.id] else {
            lastError = .productsUnavailable
            return .failed(.productsUnavailable)
        }
        guard AppStore.canMakePayments else {
            lastError = .notAllowed
            return .failed(.notAllowed)
        }

        do {
            switch try await storeProduct.purchase() {
            case let .success(verification):
                guard case let .verified(transaction) = verification else {
                    Self.logger.error("Purchase returned an unverified transaction; unlocking nothing")
                    lastError = .verificationFailed
                    return .failed(.verificationFailed)
                }
                await transaction.finish()
                await refreshEntitlement()
                lastError = nil
                return .purchased

            case .pending:
                // Ask-to-Buy, or a bank that wants a second factor. Nothing is unlocked; the
                // updates listener picks it up if and when it is approved.
                return .pending

            case .userCancelled:
                return .cancelled

            @unknown default:
                return .failed(.purchaseFailed("Unrecognised result."))
            }
        } catch {
            Self.logger.error("Purchase failed: \(String(describing: error), privacy: .public)")
            let failure = SubscriptionError.purchaseFailed(error.localizedDescription)
            lastError = failure
            return .failed(failure)
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            // A failed sync is not a reason to revoke: the last verified entitlement stands.
            Self.logger.info("AppStore.sync failed: \(String(describing: error), privacy: .public)")
        }
        await refreshEntitlement()
    }

    // MARK: - Entitlement

    func refreshEntitlement() async {
        var resolved: EntitlementState?

        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result else { continue }
            guard AppConfiguration.subscriptionProductIdentifiers.contains(transaction.productID)
            else { continue }

            if let revocation = transaction.revocationDate {
                Self.logger.info("Entitlement revoked at \(revocation, privacy: .public)")
                resolved = EntitlementState(
                    tier: .free, reason: .revoked, productIdentifier: transaction.productID,
                    lastVerifiedAt: clock.now
                )
                continue
            }

            if let expiry = transaction.expirationDate, expiry <= clock.now {
                resolved = EntitlementState(
                    tier: .free, reason: .expired, renewalOrExpirationDate: expiry,
                    productIdentifier: transaction.productID, lastVerifiedAt: clock.now
                )
                continue
            }

            resolved = .pro(
                reason: .active,
                // Only what StoreKit gave us. Nil stays nil.
                renewalOrExpirationDate: transaction.expirationDate,
                productIdentifier: transaction.productID,
                lastVerifiedAt: clock.now
            )
            break
        }

        if let resolved {
            entitlement = resolved
            cache(resolved)
            return
        }

        // Nothing came back. That is either "never subscribed" or "cannot reach the App Store".
        // A previously verified Pro entitlement survives the second case.
        if let cached = Self.loadCachedEntitlement(from: defaults), cached.isPro {
            entitlement = EntitlementState.pro(
                reason: .usingLastVerified,
                renewalOrExpirationDate: cached.renewalOrExpirationDate,
                productIdentifier: cached.productIdentifier,
                lastVerifiedAt: cached.lastVerifiedAt
            )
            return
        }

        entitlement = .free
        cache(.free)
    }

    private func cache(_ state: EntitlementState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.cachedEntitlementKey)
    }

    private static func loadCachedEntitlement(from defaults: UserDefaults) -> EntitlementState? {
        guard let data = defaults.data(forKey: cachedEntitlementKey) else { return nil }
        return try? JSONDecoder().decode(EntitlementState.self, from: data)
    }
}

/// Deterministic stand-in for previews and the UI test suite.
@MainActor
@Observable
final class StubSubscriptionService: SubscriptionProviding {
    var entitlement: EntitlementState
    var products: [SubscriptionProduct]
    var isLoadingProducts = false
    var lastError: SubscriptionError?
    var purchaseOutcome: PurchaseResult = .purchased
    private(set) var restoreCount = 0

    init(entitlement: EntitlementState = .free, products: [SubscriptionProduct]? = nil) {
        self.entitlement = entitlement
        self.products = products ?? Self.sampleProducts
    }

    func loadProducts() async {}

    func purchase(_ product: SubscriptionProduct) async -> PurchaseResult {
        if case .purchased = purchaseOutcome {
            entitlement = .pro(reason: .active, productIdentifier: product.id)
        }
        return purchaseOutcome
    }

    func restore() async {
        restoreCount += 1
    }

    func refreshEntitlement() async {}
    func startObservingTransactions() {}

    static let sampleProducts: [SubscriptionProduct] = [
        SubscriptionProduct(
            id: AppConfiguration.monthlyProductIdentifier,
            displayName: "Pro Monthly",
            description: "Unlimited open rentals and the full audit workflow.",
            displayPrice: "$14.99",
            period: .month
        ),
        SubscriptionProduct(
            id: AppConfiguration.annualProductIdentifier,
            displayName: "Pro Annual",
            description: "Unlimited open rentals and the full audit workflow, billed yearly.",
            displayPrice: "$119.99",
            period: .year,
            monthlyEquivalentPrice: "$10.00"
        ),
    ]
}
