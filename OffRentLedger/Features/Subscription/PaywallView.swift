import StoreKit
import SwiftUI

/// The subscription screen.
///
/// Every price on it comes from `Product.displayPrice`. There is no countdown, no preselected
/// option, no "most popular" badge doing the work of a decision, and no review prompt afterwards.
/// The annual plan is marked as better value with its own per-month figure, and that is the whole
/// persuasion budget.
///
/// The reassurance about existing data is not marketing. It is the single most important thing a
/// contractor looking at this screen needs to know, so it sits above the buttons rather than in a
/// footer nobody reads.
struct PaywallView: View {

    let reason: PaywallReason

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var selectedProductID: String?
    @State private var isPurchasing = false
    @State private var message: String?
    @State private var showingLegal: LegalDocument?

    private var service: any SubscriptionProviding { dependencies.subscriptions }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.roomy) {
                    header
                    entitlementStatus
                    featureList
                    reassurance
                    productList
                    secondaryActions
                    terms
                }
                .padding(.horizontal, Space.comfortable)
                .padding(.top, Space.comfortable)
                .padding(.bottom, Space.screenBottom)
            }
            .offRentScreen()
            // Subscribe stays in reach: the plans are two thirds of the way down a screen that
            // scrolls, and a purchase button below the terms is a purchase button nobody finds.
            .safeAreaInset(edge: .bottom) { purchaseBar }
            .navigationTitle("\(AppConfiguration.displayName) Pro")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier(A11yID.Paywall.root)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier(A11yID.Paywall.dismiss)
                }
            }
            .task { await service.loadProducts() }
            .sheet(item: $showingLegal) { document in
                NavigationStack { LegalDocumentView(document: document) }
            }
            .alert(
                "Subscription",
                isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    // MARK: - Sections

    /// The one graphite panel on the screen, carrying why the user is looking at it.
    private var header: some View {
        VStack(alignment: .leading, spacing: Space.snug) {
            Text("\(AppConfiguration.displayName) Pro")
                .font(Typography.caption.weight(.semibold))
                .foregroundStyle(Palette.accent)
            Text(reason.headline)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Palette.onGraphite)
                .fixedSize(horizontal: false, vertical: true)
            if reason == .openItemLimit {
                Text("""
                    The free plan tracks one open rental at a time. Resolve or archive the one you \
                    have, or subscribe for unlimited open rentals.
                    """)
                .font(Typography.rowDetail)
                .foregroundStyle(Palette.onGraphiteSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .offRentPanel()
    }

    @ViewBuilder
    private var entitlementStatus: some View {
        let entitlement = dependencies.effectiveEntitlement
        if entitlement.isPro {
            VStack(alignment: .leading, spacing: 4) {
                Label("Pro is active", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.settled)
                Text(entitlement.reason.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Only shown when StoreKit actually supplied a date. The app never computes one.
                if let date = entitlement.renewalOrExpirationDate {
                    Text("Renews or expires \(Formatters.mediumDate(date))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .offRentCard()
            .accessibilityIdentifier(A11yID.Paywall.entitlementStatus)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: Space.comfortable) {
            ForEach(ProFeature.allCases, id: \.self) { feature in
                HStack(alignment: .top, spacing: Space.base) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: Layout.symbolInline + 3))
                        .foregroundStyle(Palette.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Space.hair) {
                        Text(feature.displayName).font(Typography.rowTitle)
                        Text(feature.explanation)
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .offRentCard()
    }

    private var reassurance: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.open")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(AppCopy.entitlementLossReassurance)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .offRentCard()
        .accessibilityIdentifier(A11yID.Paywall.dataReassurance)
    }

    @ViewBuilder
    private var productList: some View {
        if service.isLoadingProducts {
            ProgressView("Loading options…").frame(maxWidth: .infinity)
        } else if service.products.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Subscription options could not be loaded.")
                    .font(.subheadline.weight(.medium))
                Text("Check your connection and try again. Nothing you already have is affected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Try again") { Task { await service.loadProducts() } }
                    .buttonStyle(.bordered)
                    .minimumTapTarget()
            }
            .offRentCard()
        } else {
            VStack(spacing: 10) {
                ForEach(service.products) { product in
                    productRow(product)
                }
            }
        }
    }

    private func productRow(_ product: SubscriptionProduct) -> some View {
        Button {
            selectedProductID = product.id
        } label: {
            HStack(alignment: .top) {
                Image(systemName: selectedProductID == product.id ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selectedProductID == product.id ? Palette.accent : .secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(product.period.displayName).font(.subheadline.weight(.semibold))
                        if product.isAnnual {
                            Text("Better value")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Palette.accent.opacity(0.15), in: Capsule())
                                .foregroundStyle(Palette.accent)
                        }
                    }
                    Text(product.period.renewalDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let monthly = product.monthlyEquivalentPrice {
                        Text("\(monthly) per month, billed yearly")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: Space.snug)
                Text(product.displayPrice)
                    .font(.headline)
                    .monospacedDigit()
            }
            .padding(Space.comfortable - 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.card))
            // The selected plan gets a real border rather than only a filled radio dot. At arm's
            // length in a truck the dot is four points of difference.
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(
                        selectedProductID == product.id ? Palette.accent : Palette.hairline,
                        lineWidth: selectedProductID == product.id ? 2 : Layout.hairline
                    )
            )
        }
        .buttonStyle(.plain)
        .minimumTapTarget()
        .accessibilityIdentifier(
            product.isAnnual ? A11yID.Paywall.annual : A11yID.Paywall.monthly
        )
        .accessibilityAddTraits(selectedProductID == product.id ? [.isSelected, .isButton] : .isButton)
    }

    private var purchaseBar: some View {
        StickyActionBar {
            VStack(spacing: Space.snug) {
                Button {
                    Task { await purchase() }
                } label: {
                    HStack(spacing: Space.snug) {
                        if isPurchasing { ProgressView().tint(Palette.onAccent) }
                        Text(isPurchasing ? "Working…" : "Subscribe")
                    }
                }
                // `.borderedProminent` painted white on the accent orange: 2.4:1, which fails at
                // any size. The house style puts graphite on orange at 7.4:1.
                .buttonStyle(.offRentPrimary)
                .accessibilityIdentifier(A11yID.Paywall.purchase)
                // Nothing is preselected, so this stays disabled until the user chooses. A
                // default selection on a purchase button is a nudge toward a charge they did
                // not pick.
                .disabled(selectedProductID == nil || isPurchasing)
                if selectedProductID == nil {
                    Text("Choose a plan above.")
                        .font(Typography.micro)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var secondaryActions: some View {
        VStack(spacing: Space.base) {
            Button("Restore purchases") {
                Task {
                    await service.restore()
                    message = dependencies.effectiveEntitlement.isPro
                        ? "Pro is active on this Apple Account."
                        : "No active subscription was found on this Apple Account."
                }
            }
            .accessibilityIdentifier(A11yID.Paywall.restore)
            .minimumTapTarget()

            if dependencies.effectiveEntitlement.isPro,
               let url = AppConfiguration.manageSubscriptionsURL {
                Button("Manage subscription") { openURL(url) }
                    .accessibilityIdentifier(A11yID.Paywall.manage)
                    .minimumTapTarget()
            }
        }
    }

    private var terms: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppCopy.subscriptionTerms)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 18) {
                Button("Privacy Policy") { showingLegal = .privacy }
                    .accessibilityIdentifier(A11yID.Paywall.privacy)
                Button("Terms of Use") { showingLegal = .terms }
                    .accessibilityIdentifier(A11yID.Paywall.terms)
            }
            .font(.caption)
            .minimumTapTarget()
        }
    }

    private func purchase() async {
        guard let selectedProductID,
              let product = service.products.first(where: { $0.id == selectedProductID })
        else { return }

        isPurchasing = true
        defer { isPurchasing = false }

        switch await service.purchase(product) {
        case .purchased:
            dismiss()
        case .pending:
            message = """
                That purchase is waiting for approval. Nothing has been unlocked yet — \
                \(AppConfiguration.displayName) will update itself when it is approved.
                """
        case .cancelled:
            break
        case let .failed(error):
            message = error.message
        }
    }
}

#Preview {
    PaywallView(reason: .openItemLimit)
        .environment(AppDependencies.preview(entitlement: .free))
}
