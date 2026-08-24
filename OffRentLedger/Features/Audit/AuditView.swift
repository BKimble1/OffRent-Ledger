import SwiftData
import SwiftUI

/// Invoices, possible mismatches and open follow-ups.
struct AuditView: View {

    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router

    @Query(sort: \VendorInvoice.receivedDate, order: .reverse) private var invoices: [VendorInvoice]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.section) {
                if !EntitlementPolicy.isAllowed(
                    .invoiceAudit, entitlement: dependencies.effectiveEntitlement
                ) {
                    ListGroup {
                        ProUpsellRow(
                            feature: .invoiceAudit,
                            reason: .invoiceAudit,
                            onTap: { router.presentedSheet = .paywall(reason: $0) }
                        )
                    }
                }

                if invoices.isEmpty {
                    EmptyStateView(
                        symbol: "checklist",
                        title: "No invoices yet",
                        message: """
                            When a final invoice arrives, attach it to the rental it belongs to. \
                            \(AppConfiguration.displayName) will lay it out next to the terms you \
                            confirmed so you can see anything worth a second look.
                            """
                    )
                    .padding(.top, Space.roomy)
                } else {
                    if !awaitingReview.isEmpty {
                        section(
                            title: "Awaiting review",
                            subtitle: """
                                Compare each invoice against the terms you confirmed while the \
                                details are still fresh.
                                """,
                            invoices: awaitingReview
                        )
                        .accessibilityIdentifier(A11yID.Audit.awaitingReview)
                    }
                    if !withOpenFindings.isEmpty {
                        section(
                            title: "Possible mismatches",
                            subtitle: AppCopy.possibleMismatchExplanation,
                            invoices: withOpenFindings
                        )
                        .accessibilityIdentifier(A11yID.Audit.possibleMismatches)
                    }
                    if !resolvedHistory.isEmpty {
                        section(title: "Resolved", subtitle: nil, invoices: resolvedHistory)
                            .accessibilityIdentifier(A11yID.Audit.resolvedHistory)
                    }
                }
            }
            .padding(.horizontal, Space.comfortable)
            .padding(.top, Space.screenTop)
            .padding(.bottom, Space.screenBottom)
        }
        .offRentScreen()
        .navigationTitle("Audit")
        .navigationBarTitleDisplayMode(.large)
        .accessibilityIdentifier(A11yID.Audit.root)
        .offRentNavigationDestinations()
    }

    private func section(
        title: String, subtitle: String?, invoices sectionInvoices: [VendorInvoice]
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.base) {
            SectionHeader(title: title, subtitle: subtitle, count: sectionInvoices.count)
            ListGroup {
                ForEach(Array(sectionInvoices.enumerated()), id: \.element.id) { index, invoice in
                    NavigationLink(value: AuditDestination.invoice(id: invoice.id)) {
                        row(invoice)
                    }
                    .buttonStyle(.plain)
                    .minimumTapTarget()
                    if index < sectionInvoices.count - 1 { RowDivider() }
                }
            }
        }
    }

    private func row(_ invoice: VendorInvoice) -> some View {
        let open: Int = invoice.openDiscrepancyCount
        return HStack(alignment: .top, spacing: Space.base) {
            RowIcon(
                symbol: open > 0 ? "exclamationmark.triangle.fill" : "list.clipboard",
                tint: open > 0 ? Palette.attention : Palette.review
            )
            VStack(alignment: .leading, spacing: Space.tight) {
                Text(invoice.invoiceNumber ?? "Invoice")
                    .font(Typography.rowTitle)
                    .lineLimit(1)
                Text(invoice.agreement?.vendor?.name ?? "Unknown vendor")
                    .font(Typography.rowDetail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: Space.tight) {
                    Text(invoice.reviewStatus.displayName)
                        .font(Typography.caption.weight(.semibold))
                        .foregroundStyle(open > 0 ? Palette.attention : .secondary)
                    if open > 0 {
                        Text("·").font(Typography.caption).foregroundStyle(.tertiary)
                        Text(open == 1 ? "1 open" : "\(open) open")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.attention)
                    }
                }
                .lineLimit(1)
            }
            Spacer(minLength: Space.snug)
            Text(Formatters.currency(invoice.invoiceTotal))
                .font(Typography.rowTitle)
                .monospacedDigit()
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(Typography.micro.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 3)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Space.comfortable)
        .padding(.vertical, Space.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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
                RowIcon(symbol: "lock.fill")
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
            .padding(.horizontal, Space.comfortable)
            .padding(.vertical, Space.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .minimumTapTarget()
        .accessibilityHint("Opens \(AppConfiguration.displayName) Pro options.")
    }
}
