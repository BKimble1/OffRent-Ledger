import SwiftData
import SwiftUI

/// The side-by-side review.
///
/// Contract, off-rent confirmation, pickup and invoice, laid out next to each other with the
/// difference stated plainly. Everything the app says here is a prompt to look, never a verdict:
/// the user decides whether to accept a difference, record a follow-up, or leave it open.
struct InvoiceReviewView: View {

    let invoiceID: UUID

    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context

    @Query private var invoices: [VendorInvoice]
    @Query private var allItems: [RentalItem]

    @State private var followUpReason = ""
    @State private var showingFollowUp = false
    @State private var rejection: TransitionRejection?

    init(invoiceID: UUID) {
        self.invoiceID = invoiceID
        _invoices = Query(filter: #Predicate<VendorInvoice> { $0.id == invoiceID })
    }

    private var invoice: VendorInvoice? { invoices.first }

    private var item: RentalItem? {
        guard let invoice else { return nil }
        if let primaryItemID = invoice.primaryItemID {
            return allItems.first { $0.id == primaryItemID }
        }
        return invoice.agreement?.items?.first
    }

    private var comparison: InvoiceComparison? {
        guard let invoice, let item else { return nil }
        let events = item.sortedEvents
        return InvoiceComparisonEngine.compare(
            InvoiceComparisonInput(
                terms: item.terms,
                confirmationDate: events.last { $0.type == .vendorConfirmationRecorded }?.timestamp,
                pickupDate: events.last { $0.type == .pickupRecorded }?.timestamp,
                invoice: invoice.value,
                expectedRentalSubtotalOverride: invoice.expectedRentalSubtotalOverride,
                calendar: dependencies.clock.calendar,
                now: dependencies.clock.now
            )
        )
    }

    var body: some View {
        List {
            if let comparison {
                varianceSection(comparison)
                comparisonSection(comparison)
                if !comparison.reviewFlags.isEmpty { reviewFlagsSection(comparison) }
                if !comparison.findings.isEmpty { findingsSection(comparison) }
            }
            linesSection
            recordedFindingsSection
            actionsSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(invoice?.invoiceNumber ?? "Invoice")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingFollowUp) { followUpSheet }
        .alert(
            "Cannot resolve yet",
            isPresented: Binding(get: { rejection != nil }, set: { if !$0 { rejection = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(rejection?.message ?? "")
        }
        .onAppear {
            // Opening the review is what moves an invoice out of "not reviewed". It is a state
            // change the user caused, so it is recorded rather than inferred later.
            if let invoice, invoice.reviewStatus == .notReviewed {
                invoice.reviewStatusRaw = InvoiceReviewStatus.inReview.rawValue
                try? context.save()
            }
        }
    }

    // MARK: - Sections

    private func varianceSection(_ comparison: InvoiceComparison) -> some View {
        Section {
            EstimateLabel(amount: comparison.possibleVariance)
                .accessibilityIdentifier(A11yID.Audit.possibleVariance)
            if comparison.possibleVariance == .zero, comparison.findings.isEmpty {
                Label(
                    "This invoice matches the terms you confirmed.",
                    systemImage: "checkmark.circle"
                )
                .font(.footnote)
                .foregroundStyle(Palette.settled)
            }
        } header: {
            Text("Possible variance")
        } footer: {
            Text(AppCopy.possibleMismatchExplanation)
        }
    }

    private func comparisonSection(_ comparison: InvoiceComparison) -> some View {
        Section {
            DetailRow(
                label: "Expected rental amount",
                value: comparison.expectedRentalSubtotal.map(Formatters.currency) ?? "Not available"
            )
            DetailRow(
                label: "Invoiced rental amount",
                value: Formatters.currency(comparison.invoicedRentalSubtotal)
            )
            DetailRow(label: "Invoice total", value: Formatters.currency(comparison.invoiceTotal))
            DetailRow(label: "Sum of the lines", value: Formatters.currency(comparison.lineSum))
            if let through = comparison.expectedBilledThroughDate {
                DetailRow(label: "Expected billed through", value: Formatters.mediumDate(through))
            }
            if let invoice, let billedThrough = invoice.billedThroughDate {
                DetailRow(
                    label: "Invoice billed through",
                    value: Formatters.mediumDate(billedThrough)
                )
            }
            Text(comparison.expectationBasis)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("Side by side")
        }
        .accessibilityIdentifier(A11yID.Audit.comparisonTable)
    }

    private func reviewFlagsSection(_ comparison: InvoiceComparison) -> some View {
        Section {
            ForEach(comparison.reviewFlags) { flag in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(flag.category.displayName).font(.subheadline.weight(.medium))
                        Spacer()
                        Text(Formatters.currency(flag.amount)).monospacedDigit()
                    }
                    Text(flag.prompt).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button("Accept") { setLineState(flag.lineID, to: .accepted) }
                            .buttonStyle(.bordered)
                            .minimumTapTarget()
                        Button("Question") { setLineState(flag.lineID, to: .questioned) }
                            .buttonStyle(.bordered)
                            .minimumTapTarget()
                    }
                }
                .padding(.vertical, 2)
                .accessibilityIdentifier(A11yID.Audit.line(flag.lineID))
            }
        } header: {
            Text(AppCopy.reviewThisCharge)
        } footer: {
            Text("""
                \(AppConfiguration.displayName) has no basis to have an opinion about these \
                charges, so it is not calling them mismatches. Work through them and mark each one.
                """)
        }
    }

    private func findingsSection(_ comparison: InvoiceComparison) -> some View {
        Section("Possible mismatches found") {
            ForEach(comparison.findings) { finding in
                VStack(alignment: .leading, spacing: 5) {
                    Text(finding.type.displayName).font(.subheadline.weight(.medium))
                    if let expected = finding.expectedAmount, let invoiced = finding.invoicedAmount {
                        HStack {
                            Text("Expected \(Formatters.currency(expected))")
                            Spacer()
                            Text("Invoiced \(Formatters.currency(invoiced))")
                        }
                        .font(.caption)
                        .monospacedDigit()
                    }
                    Text(finding.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Button("Accept this") { accept(finding) }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier(A11yID.Audit.acceptMismatch)
                            .minimumTapTarget()
                        Button("Record a follow-up") { showingFollowUp = true }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier(A11yID.Audit.recordFollowUp)
                            .minimumTapTarget()
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var linesSection: some View {
        Section("Lines you entered") {
            if let invoice, let lines = invoice.lines, !lines.isEmpty {
                ForEach(lines.sorted(by: { $0.sortIndex < $1.sortIndex }), id: \.id) { line in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.category.displayName).font(.subheadline)
                            if !line.detail.isEmpty {
                                Text(line.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            if line.reviewState != .unreviewed {
                                Text(line.reviewState.displayName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(Formatters.currency(line.amount)).monospacedDigit()
                    }
                }
            } else {
                Text("No lines were entered for this invoice.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var recordedFindingsSection: some View {
        Group {
            if let invoice, let recorded = invoice.discrepancies, !recorded.isEmpty {
                Section("Recorded follow-ups") {
                    ForEach(recorded, id: \.id) { discrepancy in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(discrepancy.type.displayName).font(.subheadline)
                                Spacer()
                                Text(discrepancy.status.displayName)
                                    .font(.caption)
                                    .foregroundStyle(discrepancy.status.isOpen ? Palette.attention : .secondary)
                            }
                            if let difference = discrepancy.difference {
                                Text("Difference \(Formatters.currency(difference))")
                                    .font(.caption)
                                    .monospacedDigit()
                            }
                            if let notes = discrepancy.resolutionNotes, !notes.isEmpty {
                                Text(notes).font(.caption).foregroundStyle(.secondary)
                            }
                            if discrepancy.status.isOpen {
                                Button("Mark resolved") { resolve(discrepancy) }
                                    .buttonStyle(.bordered)
                                    .minimumTapTarget()
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .accessibilityIdentifier(A11yID.Audit.followUps)
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button("Accept this invoice") { acceptInvoice() }
                .accessibilityIdentifier(A11yID.Audit.resolveInvoice)
                .minimumTapTarget()
            if let item {
                NavigationLink("Open the rental", value: RentalDestination.item(id: item.id))
                    .minimumTapTarget()
            }
        } footer: {
            Text("""
                Accepting records that you looked at this invoice and were satisfied. It does not \
                pay anything and does not tell the vendor anything.
                """)
        }
    }

    private var followUpSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What needs following up?", text: $followUpReason, axis: .vertical)
                        .lineLimit(3...8)
                        .accessibilityIdentifier(A11yID.Audit.followUpReason)
                } footer: {
                    Text("""
                        This is your own note. It goes into the timeline and into the evidence \
                        packet, and it keeps the rental open until you close it out.
                        """)
                }
            }
            .navigationTitle("Record a follow-up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingFollowUp = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { recordFollowUp() }
                        .disabled(followUpReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Actions

    private func setLineState(_ lineID: UUID, to state: LineReviewState) {
        guard let line = invoice?.lines?.first(where: { $0.id == lineID }) else { return }
        line.reviewStateRaw = state.rawValue
        try? context.save()
    }

    private func accept(_ finding: DiscrepancyValue) {
        guard let invoice else { return }
        var accepted = finding
        accepted.status = .accepted
        accepted.resolvedAt = dependencies.clock.now
        let record = Discrepancy(value: accepted, itemID: item?.id, invoice: invoice)
        context.insert(record)
        if let item {
            RentalWorkflowService(context: context, clock: dependencies.clock)
                .append(event: .mismatchAccepted, to: item, detail: finding.type.displayName)
        }
        try? context.save()
    }

    private func recordFollowUp() {
        guard let invoice, let item, let comparison else { return }
        let workflow = RentalWorkflowService(context: context, clock: dependencies.clock)

        // The open findings are written down at the moment the user records the follow-up, so
        // the record survives a later edit to the terms that would change the recomputation.
        for finding in comparison.openFindings {
            var stored = finding
            stored.status = .followUpRecorded
            stored.resolutionNotes = followUpReason
            context.insert(Discrepancy(value: stored, itemID: item.id, invoice: invoice))
        }
        invoice.reviewStatusRaw = InvoiceReviewStatus.followUpRecorded.rawValue

        switch workflow.apply(.flagFollowUp(reason: followUpReason), to: item) {
        case .success:
            try? context.save()
            followUpReason = ""
            showingFollowUp = false
        case let .failure(failure):
            rejection = failure
        }
    }

    private func resolve(_ discrepancy: Discrepancy) {
        discrepancy.discrepancyStatusRaw = DiscrepancyStatus.resolved.rawValue
        discrepancy.resolvedAt = dependencies.clock.now
        try? context.save()
    }

    private func acceptInvoice() {
        guard let invoice else { return }
        let openCount = invoice.openDiscrepancyCount
        guard openCount == 0 else {
            rejection = .cannotResolveWithOpenDiscrepancies(count: openCount)
            return
        }
        invoice.reviewStatusRaw = InvoiceReviewStatus.accepted.rawValue
        invoice.reviewedAt = dependencies.clock.now
        try? context.save()
    }
}
