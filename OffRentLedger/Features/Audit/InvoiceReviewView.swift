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
        let confirmedAt: Date? = events.last { $0.type == .vendorConfirmationRecorded }?.timestamp
        let pickedUpAt: Date? = events.last { $0.type == .pickupRecorded }?.timestamp
        return InvoiceComparisonEngine.compare(
            InvoiceComparisonInput(
                terms: item.terms,
                confirmationDate: confirmedAt,
                pickupDate: pickedUpAt,
                invoice: invoice.value,
                expectedRentalSubtotalOverride: invoice.expectedRentalSubtotalOverride,
                calendar: dependencies.clock.calendar,
                now: dependencies.clock.now
            )
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.section) {
                if let comparison {
                    varianceSection(comparison)
                    comparisonSection(comparison)
                    if !comparison.reviewFlags.isEmpty { reviewFlagsSection(comparison) }
                    if !comparison.findings.isEmpty { findingsSection(comparison) }
                }
                linesSection
                recordedFindingsSection
                openRentalLink
                acceptExplanation
            }
            .padding(.horizontal, Space.comfortable)
            .padding(.top, Space.screenTop)
            .padding(.bottom, Space.screenBottom)
        }
        .offRentScreen()
        .safeAreaInset(edge: .bottom) { acceptBar }
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

    /// The answer, first, and the qualification with it.
    private func varianceSection(_ comparison: InvoiceComparison) -> some View {
        VStack(alignment: .leading, spacing: Space.base) {
            VariancePanel(
                expected: comparison.expectedRentalSubtotal,
                invoiced: comparison.invoicedRentalSubtotal,
                variance: comparison.possibleVariance,
                isMatch: comparison.possibleVariance == .zero && comparison.findings.isEmpty,
                identifier: A11yID.Audit.possibleVariance
            )
            if comparison.possibleVariance == .zero, comparison.findings.isEmpty {
                InlineAlert(
                    message: "This invoice matches the terms you confirmed.",
                    kind: .positive
                )
            }
            Text(AppCopy.possibleMismatchExplanation)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Space.tight)
        }
    }

    private func comparisonSection(_ comparison: InvoiceComparison) -> some View {
        section(title: "Side by side", subtitle: comparison.expectationBasis) {
            DetailRow(
                label: "Expected rental amount",
                value: comparison.expectedRentalSubtotal.map(Formatters.currency) ?? "Not available"
            )
            RowDivider(inset: Space.comfortable)
            DetailRow(
                label: "Invoiced rental amount",
                value: Formatters.currency(comparison.invoicedRentalSubtotal)
            )
            RowDivider(inset: Space.comfortable)
            DetailRow(label: "Invoice total", value: Formatters.currency(comparison.invoiceTotal))
            RowDivider(inset: Space.comfortable)
            DetailRow(label: "Sum of the lines", value: Formatters.currency(comparison.lineSum))
            if let through = comparison.expectedBilledThroughDate {
                RowDivider(inset: Space.comfortable)
                DetailRow(label: "Expected billed through", value: Formatters.mediumDate(through))
            }
            if let invoice, let billedThrough = invoice.billedThroughDate {
                RowDivider(inset: Space.comfortable)
                DetailRow(
                    label: "Invoice billed through",
                    value: Formatters.mediumDate(billedThrough)
                )
            }
        }
        // `.contain` first: without it this identifier is pushed down onto all five DetailRows
        // and each one loses its own. The last accessibility dump showed exactly that — five
        // separate elements all called "audit.comparisonTable".
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11yID.Audit.comparisonTable)
    }

    private func reviewFlagsSection(_ comparison: InvoiceComparison) -> some View {
        section(
            title: AppCopy.reviewThisCharge,
            subtitle: """
                \(AppConfiguration.displayName) has no basis to have an opinion about these \
                charges, so it is not calling them mismatches. Work through them and mark each one.
                """
        ) {
            ForEach(Array(comparison.reviewFlags.enumerated()), id: \.element.id) { index, flag in
                VStack(alignment: .leading, spacing: Space.snug) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(flag.category.displayName).font(Typography.rowTitle)
                        Spacer(minLength: Space.snug)
                        Text(Formatters.currency(flag.amount))
                            .font(Typography.rowTitle)
                            .monospacedDigit()
                    }
                    Text(flag.prompt)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Space.snug) {
                        Button("Accept") { setLineState(flag.lineID, to: .accepted) }
                            .buttonStyle(.offRentSecondary)
                        Button("Question") { setLineState(flag.lineID, to: .questioned) }
                            .buttonStyle(.offRentSecondary)
                    }
                }
                .padding(.horizontal, Space.comfortable)
                .padding(.vertical, Space.base)
                .accessibilityIdentifier(A11yID.Audit.line(flag.lineID))
                if index < comparison.reviewFlags.count - 1 { RowDivider(inset: Space.comfortable) }
            }
        }
    }

    private func findingsSection(_ comparison: InvoiceComparison) -> some View {
        section(title: "Possible mismatches found") {
            ForEach(Array(comparison.findings.enumerated()), id: \.element.id) { index, finding in
                VStack(alignment: .leading, spacing: Space.snug) {
                    Text(finding.type.displayName).font(Typography.rowTitle)
                    if let expected = finding.expectedAmount, let invoiced = finding.invoicedAmount {
                        HStack {
                            Text("Expected \(Formatters.currency(expected))")
                            Spacer(minLength: Space.snug)
                            Text("Invoiced \(Formatters.currency(invoiced))")
                        }
                        .font(Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    }
                    Text(finding.explanation)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Space.snug) {
                        Button("Accept this") { accept(finding) }
                            .buttonStyle(.offRentSecondary)
                            .accessibilityIdentifier(A11yID.Audit.acceptMismatch)
                        Button("Record a follow-up") { showingFollowUp = true }
                            .buttonStyle(.offRentSecondary)
                            .accessibilityIdentifier(A11yID.Audit.recordFollowUp)
                    }
                }
                .padding(.horizontal, Space.comfortable)
                .padding(.vertical, Space.base)
                if index < comparison.findings.count - 1 { RowDivider(inset: Space.comfortable) }
            }
        }
    }

    private var linesSection: some View {
        section(title: "Lines you entered") {
            if let invoice, let lines = invoice.lines, !lines.isEmpty {
                let sorted: [InvoiceLine] = lines.sorted(by: { $0.sortIndex < $1.sortIndex })
                ForEach(Array(sorted.enumerated()), id: \.element.id) { index, line in
                    HStack(alignment: .top, spacing: Space.base) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.category.displayName).font(Typography.rowTitle)
                            if !line.detail.isEmpty {
                                Text(line.detail)
                                    .font(Typography.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if line.reviewState != .unreviewed {
                                Text(line.reviewState.displayName)
                                    .font(Typography.micro.weight(.semibold))
                                    .foregroundStyle(Palette.review)
                            }
                        }
                        Spacer(minLength: Space.snug)
                        Text(Formatters.currency(line.amount))
                            .font(Typography.rowTitle)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, Space.comfortable)
                    .padding(.vertical, Space.base)
                    if index < sorted.count - 1 { RowDivider(inset: Space.comfortable) }
                }
            } else {
                Text("No lines were entered for this invoice.")
                    .font(Typography.rowDetail)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.comfortable)
                    .padding(.vertical, Space.base)
            }
        }
    }

    @ViewBuilder
    private var recordedFindingsSection: some View {
        if let invoice, let recorded = invoice.discrepancies, !recorded.isEmpty {
            section(title: "Recorded follow-ups") {
                ForEach(Array(recorded.enumerated()), id: \.element.id) { index, discrepancy in
                    VStack(alignment: .leading, spacing: Space.snug) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(discrepancy.type.displayName).font(Typography.rowTitle)
                            Spacer(minLength: Space.snug)
                            Text(discrepancy.status.displayName)
                                .font(Typography.caption.weight(.semibold))
                                .foregroundStyle(
                                    discrepancy.status.isOpen ? Palette.attention : .secondary
                                )
                        }
                        if let difference = discrepancy.difference {
                            Text("Difference \(Formatters.currency(difference))")
                                .font(Typography.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        if let notes = discrepancy.resolutionNotes, !notes.isEmpty {
                            Text(notes)
                                .font(Typography.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if discrepancy.status.isOpen {
                            Button("Mark resolved") { resolve(discrepancy) }
                                .buttonStyle(.offRentSecondary)
                                .padding(.top, Space.tight)
                        }
                    }
                    .padding(.horizontal, Space.comfortable)
                    .padding(.vertical, Space.base)
                    if index < recorded.count - 1 { RowDivider(inset: Space.comfortable) }
                }
            }
            .accessibilityIdentifier(A11yID.Audit.followUps)
        }
    }

    @ViewBuilder
    private var openRentalLink: some View {
        if let item {
            ListGroup {
                NavigationLink(value: RentalDestination.item(id: item.id)) {
                    NavigationRow(title: "Open the rental", symbol: "shippingbox")
                }
                .buttonStyle(.plain)
                .minimumTapTarget()
            }
        }
    }

    /// The one decision this screen exists to let somebody make, kept in reach of the thumb.
    ///
    /// The button alone. The sentence explaining what accepting does and does not do is four
    /// lines long, and putting it in the bar cost 130pt of a 852pt screen on every scroll; it
    /// reads better as the last thing in the content, immediately above this.
    private var acceptBar: some View {
        StickyActionBar {
            Button("Accept this invoice") { acceptInvoice() }
                .buttonStyle(.offRentPrimary)
                .accessibilityIdentifier(A11yID.Audit.resolveInvoice)
        }
    }

    private var acceptExplanation: some View {
        Text("""
            Accepting records that you looked at this invoice and were satisfied. It does not pay \
            anything and does not tell the vendor anything.
            """)
            .font(Typography.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.tight)
    }

    private func section(
        title: String, subtitle: String? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.base) {
            SectionHeader(title: title, subtitle: subtitle)
            ListGroup { content() }
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
            .offRentFormBackground()
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

    /// Findings on screen that nothing has been recorded against yet.
    private var unaddressedFindingCount: Int {
        guard let comparison else { return 0 }
        let recorded = Set((invoice?.discrepancies ?? []).map(\.type))
        return comparison.unaddressedFindings(recordedTypes: recorded).count
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
        // Two kinds of open, and this used to count only one of them.
        //
        // `openDiscrepancyCount` counts *stored* discrepancies, and one only exists after the
        // user has already accepted a finding or recorded a follow-up against it. So on the one
        // path this guard exists for — a fresh invoice with a live mismatch on the screen in
        // front of somebody — the count was zero and Accept went straight through without a
        // word. The UI suite caught it the first time it ever got this far.
        let openCount = invoice.openDiscrepancyCount + unaddressedFindingCount
        guard openCount == 0 else {
            rejection = .cannotResolveWithOpenDiscrepancies(count: openCount)
            return
        }
        invoice.reviewStatusRaw = InvoiceReviewStatus.accepted.rawValue
        invoice.reviewedAt = dependencies.clock.now
        try? context.save()
    }
}
