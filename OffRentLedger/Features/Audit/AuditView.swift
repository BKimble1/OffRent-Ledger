import SwiftData
import SwiftUI

/// Invoices, possible mismatches and open follow-ups.
struct AuditView: View {

    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Query(sort: \VendorInvoice.receivedDate, order: .reverse) private var invoices: [VendorInvoice]

    var body: some View {
        List {
            if !EntitlementPolicy.isAllowed(
                .invoiceAudit, entitlement: dependencies.effectiveEntitlement
            ) {
                Section {
                    ProUpsellRow(
                        feature: .invoiceAudit,
                        reason: .invoiceAudit,
                        onTap: { router.presentedSheet = .paywall(reason: $0) }
                    )
                }
            }

            if !awaitingReview.isEmpty {
                Section {
                    ForEach(awaitingReview, id: \.id) { row($0) }
                } header: {
                    Text("Awaiting review")
                } footer: {
                    Text("Compare each one against the terms you confirmed.")
                }
                .accessibilityIdentifier(A11yID.Audit.awaitingReview)
            }

            if !withOpenFindings.isEmpty {
                Section {
                    ForEach(withOpenFindings, id: \.id) { row($0) }
                } header: {
                    Text("Possible mismatches")
                } footer: {
                    Text("A possible mismatch is a prompt to look, not a determination.")
                }
                .accessibilityIdentifier(A11yID.Audit.possibleMismatches)
            }

            if !resolvedHistory.isEmpty {
                Section("Resolved") {
                    ForEach(resolvedHistory, id: \.id) { row($0) }
                }
                .accessibilityIdentifier(A11yID.Audit.resolvedHistory)
            }
        }
        .listStyle(.insetGrouped)
        .offRentFormBackground()
        .navigationTitle("Audit")
        .accessibilityIdentifier(A11yID.Audit.root)
        .offRentNavigationDestinations()
        .overlay {
            if invoices.isEmpty {
                EmptyStateView(
                    symbol: "checklist",
                    title: "No invoices yet",
                    message: """
                        Attach a final invoice to the rental it belongs to and it will be laid out \
                        next to the terms you confirmed.
                        """
                )
            }
        }
    }

    /// Two columns until they stop fitting, and then one.
    ///
    /// Every line here was held to `lineLimit(1)`, which at the accessibility text sizes clipped
    /// the invoice number, the company and the total all at once — a row of three ellipses.
    /// Nothing is clipped now: the row stacks and grows, the way `RentalRow` and `DetailRow`
    /// already do.
    private func row(_ invoice: VendorInvoice) -> some View {
        let open: Int = invoice.openDiscrepancyCount
        return NavigationLink(value: AuditDestination.invoice(id: invoice.id)) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Space.snug) {
                        rowSummary(invoice, open: open)
                        rowTotal(invoice)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: Space.base) {
                        rowSummary(invoice, open: open)
                        Spacer(minLength: Space.snug)
                        rowTotal(invoice)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        }
        .accessibilityHint(invoice.reviewStatus.displayName)
    }

    /// What the invoice is, whose it is, and where it stands.
    private func rowSummary(_ invoice: VendorInvoice, open: Int) -> some View {
        VStack(alignment: .leading, spacing: Space.hair) {
            Text(invoice.invoiceNumber ?? "Invoice")
                .font(Typography.rowTitle)
                .fixedSize(horizontal: false, vertical: true)
            Text(invoice.agreement?.vendor?.name ?? "Unknown vendor")
                .font(Typography.rowDetail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            rowStatus(invoice, open: open)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The status, and the count of lines still open on it. The interpunct between them is a
    /// width-saving device, so it goes when there is no width to save.
    @ViewBuilder
    private func rowStatus(_ invoice: VendorInvoice, open: Int) -> some View {
        let openText: String? = open == 0 ? nil : (open == 1 ? "1 open" : "\(open) open")
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(invoice.reviewStatus.displayName)
                    .foregroundStyle(.secondary)
                if let openText {
                    Text(openText).foregroundStyle(Palette.attentionText)
                }
            }
            .font(Typography.caption)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(spacing: Space.tight + 1) {
                Text(invoice.reviewStatus.displayName)
                if let openText {
                    Text("·").foregroundStyle(.tertiary)
                    Text(openText).foregroundStyle(Palette.attentionText)
                }
            }
            .font(Typography.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    private func rowTotal(_ invoice: VendorInvoice) -> some View {
        Text(Formatters.currency(invoice.invoiceTotal))
            .font(Typography.rowTitle)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }

    private var awaitingReview: [VendorInvoice] {
        invoices.filter { $0.reviewStatus == .notReviewed || $0.reviewStatus == .inReview }
    }

    private var withOpenFindings: [VendorInvoice] {
        invoices.filter { $0.openDiscrepancyCount > 0 && $0.reviewStatus != .accepted }
    }

    private var resolvedHistory: [VendorInvoice] {
        invoices.filter { $0.reviewStatus == .accepted || $0.reviewStatus == .followUpRecorded }
    }
}

struct ProUpsellRow: View {
    let feature: ProFeature
    let reason: PaywallReason
    let onTap: (PaywallReason) -> Void

    var body: some View {
        Button { onTap(reason) } label: {
            HStack(alignment: .top, spacing: Space.base) {
                RowIcon(symbol: "lock")
                VStack(alignment: .leading, spacing: Space.tight) {
                    Text(feature.displayName).font(Typography.rowTitle)
                    Text(feature.explanation)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.tight)
                Image(systemName: "chevron.right")
                    .font(Typography.micro.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 3)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .minimumTapTarget()
        .accessibilityHint("Opens \(AppConfiguration.displayName) Pro options.")
    }
}
