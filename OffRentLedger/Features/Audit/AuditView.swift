import SwiftData
import SwiftUI

/// Invoices, possible mismatches and open follow-ups.
struct AuditView: View {

    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router

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

    private func row(_ invoice: VendorInvoice) -> some View {
        let open: Int = invoice.openDiscrepancyCount
        return NavigationLink(value: AuditDestination.invoice(id: invoice.id)) {
            HStack(alignment: .firstTextBaseline, spacing: Space.base) {
                VStack(alignment: .leading, spacing: Space.hair) {
                    Text(invoice.invoiceNumber ?? "Invoice")
                        .font(Typography.rowTitle)
                        .lineLimit(1)
                    Text(invoice.agreement?.vendor?.name ?? "Unknown vendor")
                        .font(Typography.rowDetail)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: Space.tight + 1) {
                        Text(invoice.reviewStatus.displayName)
                        if open > 0 {
                            Text("·").foregroundStyle(.tertiary)
                            Text(open == 1 ? "1 open" : "\(open) open")
                                .foregroundStyle(Palette.attention)
                        }
                    }
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: Space.snug)
                Text(Formatters.currency(invoice.invoiceTotal))
                    .font(Typography.rowTitle)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .padding(.vertical, 2)
        }
        .accessibilityHint(invoice.reviewStatus.displayName)
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
