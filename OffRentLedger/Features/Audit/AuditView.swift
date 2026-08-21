import SwiftData
import SwiftUI

/// Invoices, possible mismatches and open follow-ups.
struct AuditView: View {

    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router

    @Query(sort: \VendorInvoice.receivedDate, order: .reverse) private var invoices: [VendorInvoice]

    var body: some View {
        List {
            if !EntitlementPolicy.isAllowed(.invoiceAudit, entitlement: dependencies.effectiveEntitlement) {
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
                    ForEach(awaitingReview, id: \.id) { invoice in row(invoice) }
                } header: {
                    Text("Awaiting review")
                } footer: {
                    Text("Compare each invoice against the terms you confirmed while the details are still fresh.")
                }
                .accessibilityIdentifier(A11yID.Audit.awaitingReview)
            }

            if !withOpenFindings.isEmpty {
                Section {
                    ForEach(withOpenFindings, id: \.id) { invoice in row(invoice) }
                } header: {
                    Text("Possible mismatches")
                } footer: {
                    Text(AppCopy.possibleMismatchExplanation)
                }
                .accessibilityIdentifier(A11yID.Audit.possibleMismatches)
            }

            if !resolvedHistory.isEmpty {
                Section("Resolved") {
                    ForEach(resolvedHistory, id: \.id) { invoice in row(invoice) }
                }
                .accessibilityIdentifier(A11yID.Audit.resolvedHistory)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Audit")
        .accessibilityIdentifier(A11yID.Audit.root)
        .offRentNavigationDestinations()
        .overlay {
            if invoices.isEmpty {
                EmptyStateView(
                    symbol: "checklist",
                    title: "No invoices yet",
                    message: """
                        When a final invoice arrives, attach it to the rental it belongs to. \
X
                        confirmed so you can see anything worth a second look.
                        """
                )
            }
        }
    }

    private func row(_ invoice: VendorInvoice) -> some View {
        NavigationLink(value: AuditDestination.invoice(id: invoice.id)) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(invoice.invoiceNumber ?? "Invoice")
                        .font(.body.weight(.medium))
                    Spacer(minLength: 8)
                    Text(Formatters.currency(invoice.invoiceTotal))
                        .font(.subheadline)
                        .monospacedDigit()
                }
                Text(invoice.agreement?.vendor?.name ?? "Unknown vendor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Label(invoice.reviewStatus.displayName, systemImage: "list.clipboard")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if invoice.openDiscrepancyCount > 0 {
                        Label(
                            invoice.openDiscrepancyCount == 1
                                ? "1 open"
                                : "\(invoice.openDiscrepancyCount) open",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption2)
                        .foregroundStyle(Palette.attention)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .minimumTapTarget()
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
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(feature.displayName).font(.subheadline.weight(.medium))
                    Text(feature.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .minimumTapTarget()
        .accessibilityHint("Opens \(AppConfiguration.displayName) Pro options.")
    }
}
