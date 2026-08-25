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
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query private var invoices: [VendorInvoice]
    @Query private var allItems: [RentalItem]

    @State private var followUpReason = ""
    @State private var showingFollowUp = false
    @State private var rejection: TransitionRejection?
    @State private var isAccepting = false
    @State private var showingEditInvoice = false
    @State private var justAccepted = false
    @State private var saveFailure: String?

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
                if let saveFailure {
                    Label(saveFailure, systemImage: "externaldrive.badge.exclamationmark")
                        .font(Typography.rowDetail)
                        .foregroundStyle(Palette.attentionText)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
        .sheet(isPresented: $showingEditInvoice) {
            if let item {
                AttachInvoiceSheet(itemID: item.id, editing: invoice?.id)
            } else {
                // Unreachable while the button that sets this is guarded on `item`, and present
                // anyway: a sheet whose content builder produces nothing is a blank screen the
                // user cannot dismiss.
                EmptyStateView(
                    symbol: "questionmark.folder",
                    title: "That rental is gone",
                    message: "The invoice is still here, but the rental it belongs to is not.",
                    actionTitle: "Close",
                    action: { showingEditInvoice = false }
                )
            }
        }
        .onAppear {
            // Opening the review is what moves an invoice out of "not reviewed". It is a state
            // change the user caused, so it is recorded rather than inferred later.
            if let invoice, invoice.reviewStatus == .notReviewed {
                invoice.reviewStatusRaw = InvoiceReviewStatus.inReview.rawValue
                PersistentStore.saveDerived(context, describing: "the review status")
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
            comparisonRow(
                "Expected rental amount",
                comparison.expectedRentalSubtotal.map(Formatters.currency) ?? "Not available"
            )
            RowDivider(inset: Space.comfortable)
            comparisonRow(
                "Invoiced rental amount",
                Formatters.currency(comparison.invoicedRentalSubtotal)
            )
            RowDivider(inset: Space.comfortable)
            comparisonRow("Invoice total", Formatters.currency(comparison.invoiceTotal))
            RowDivider(inset: Space.comfortable)
            comparisonRow("Sum of the lines", Formatters.currency(comparison.lineSum))
            if let through = comparison.expectedBilledThroughDate {
                RowDivider(inset: Space.comfortable)
                comparisonRow("Expected billed through", Formatters.mediumDate(through))
            }
            if let invoice, let billedThrough = invoice.billedThroughDate {
                RowDivider(inset: Space.comfortable)
                comparisonRow("Invoice billed through", Formatters.mediumDate(billedThrough))
            }
        }
        // `.contain` first: without it this identifier is pushed down onto every row and each one
        // loses its own. The last accessibility dump showed exactly that — five separate
        // elements all called "audit.comparisonTable".
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11yID.Audit.comparisonTable)
    }

    /// A label and a figure that share a row until they cannot, and then stack.
    ///
    /// `DetailRow` put both on one line with the value trailing, and the screenshot shows what
    /// that does at larger text sizes: "Expected rental amount" and "Not available" overlapping,
    /// with the value running off the right edge. `ViewThatFits` keeps the compact form wherever
    /// it genuinely fits and falls back to a stack everywhere else, so nothing ever clips.
    private func comparisonRow(_ label: String, _ value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Space.base) {
                Text(label)
                    .font(Typography.rowDetail)
                    .foregroundStyle(.secondary)
                Spacer(minLength: Space.snug)
                Text(value)
                    .font(Typography.rowTitle)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Typography.rowDetail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(value)
                    .font(Typography.rowTitle)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Space.comfortable)
        .padding(.vertical, Space.base)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
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
    /// The shipped failure was a bright orange `Accept this invoice` that did nothing at all when
    /// tapped. Three things were wrong at once, and only fixing all three makes the control
    /// honest:
    ///
    /// 1. **The decision lived inside the action.** So "refused" and "accepted" looked identical
    ///    from outside, and a refusal on the one record in the screenshot — no lines, no total —
    ///    produced no alert either. Now `InvoiceAcceptance.decide` is asked *before* the button
    ///    draws itself, and a blocked invoice is a disabled control with its reason printed under
    ///    it and a route out.
    /// 2. **Accepting changed nothing visible.** It stamped `reviewStatus` on the invoice and
    ///    stopped. Nothing on this screen read that property, the rental stayed in Invoice
    ///    Review, and the Audit counts did not move — so a tap that worked perfectly was
    ///    indistinguishable from one that did not land. Now it resolves the rental through the
    ///    workflow service, confirms in place, and pops back to Audit.
    /// 3. **It could run twice.** Two taps wrote two acceptances. `isAccepting` and the
    ///    `alreadyAccepted` decision each stop that on their own.
    private var acceptBar: some View {
        StickyActionBar {
            VStack(spacing: Space.snug) {
                if justAccepted {
                    Label(InvoiceAcceptance.confirmation, systemImage: "checkmark.circle.fill")
                        .font(Typography.rowTitle)
                        .foregroundStyle(Palette.settled)
                        .accessibilityIdentifier(A11yID.Audit.acceptedConfirmation)
                } else {
                    Button(action: acceptInvoice) {
                        // Pressed and loading feedback, rather than a button that looks the same
                        // whether or not the tap landed.
                        if isAccepting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(InvoiceAcceptance.actionTitle(acceptanceInput))
                        }
                    }
                    .buttonStyle(.offRentPrimary)
                    .disabled(acceptanceBlock != nil || isAccepting)
                    .accessibilityIdentifier(A11yID.Audit.resolveInvoice)

                    if let block = acceptanceBlock {
                        Text(block.explanation)
                            .font(Typography.micro)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier(A11yID.Audit.resolveBlockedReason)

                        // Only offered when there is a rental to hang the form off. An invoice
                        // whose item has been deleted has no editor to open, and a sheet built
                        // from an `if let` that fails presents an empty screen with no way out.
                        if let route = block.editRouteTitle, item != nil {
                            Button(route) { showingEditInvoice = true }
                                .buttonStyle(.offRentSecondary)
                                .accessibilityIdentifier(A11yID.Audit.editInvoice)
                        }
                    }
                }
            }
        }
        // The refusal alert lives on the control that raises it, not on the scroll view.
        //
        // It used to sit beside `.sheet(isPresented:)` on the same view, and the two fought:
        // after the alert had been shown and dismissed once, setting `showingFollowUp` did
        // nothing at all — the button was tapped, the action ran, and no sheet appeared.
        .alert(
            "Cannot resolve yet",
            isPresented: Binding(get: { rejection != nil }, set: { if !$0 { rejection = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(rejection?.message ?? "")
        }
    }

    /// Everything the decision depends on, gathered where it can be read.
    private var acceptanceInput: InvoiceAcceptanceInput {
        InvoiceAcceptanceInput(
            openRecordedDiscrepancies: invoice?.openDiscrepancyCount ?? 0,
            unaddressedFindings: unaddressedFindingCount,
            lineCount: invoice?.lines?.count ?? 0,
            invoiceTotal: invoice?.invoiceTotal ?? .zero,
            currentStatus: invoice?.reviewStatus ?? .notReviewed
        )
    }

    private var acceptanceBlock: InvoiceAcceptanceBlock? {
        guard invoice != nil else { return nil }
        if case let .failure(block) = InvoiceAcceptance.decide(acceptanceInput) { return block }
        return nil
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
                        packet, and it keeps the rental open until you resolve it.
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
        saveFailure = PersistentStore.save(context, describing: "That line")
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
        saveFailure = PersistentStore.save(context, describing: "That finding")
    }

    private func recordFollowUp() {
        guard let invoice, let item, let comparison else { return }
        let workflow = RentalWorkflowService(context: context, clock: dependencies.clock)

        // Ask the state machine *before* writing anything.
        //
        // This used to insert a Discrepancy for every open finding and stamp the invoice, and
        // only then ask whether the transition was allowed. On a refusal — recording a second
        // follow-up on an invoice already in Needs Follow-Up — the user was shown "Cannot do
        // that yet" and reasonably assumed nothing had happened, while a duplicate set of
        // discrepancy rows and an overwritten invoice status sat in the context waiting for
        // SwiftData to autosave them. `acceptInvoice` already rolls back rather than leaving two
        // records disagreeing; this now avoids needing to.
        if case let .failure(failure) = workflow.apply(.flagFollowUp(reason: followUpReason), to: item) {
            rejection = failure
            return
        }

        // The open findings are written down at the moment the user records the follow-up, so
        // the record survives a later edit to the terms that would change the recomputation.
        for finding in comparison.openFindings {
            var stored = finding
            stored.status = .followUpRecorded
            stored.resolutionNotes = followUpReason
            context.insert(Discrepancy(value: stored, itemID: item.id, invoice: invoice))
        }
        invoice.reviewStatusRaw = InvoiceReviewStatus.followUpRecorded.rawValue

        if let problem = PersistentStore.save(context, describing: "This follow-up") {
            saveFailure = problem
            return
        }
        saveFailure = nil
        dependencies.derivedStateNeedsRefresh()
        followUpReason = ""
        showingFollowUp = false
    }

    private func resolve(_ discrepancy: Discrepancy) {
        discrepancy.discrepancyStatusRaw = DiscrepancyStatus.resolved.rawValue
        discrepancy.resolvedAt = dependencies.clock.now
        saveFailure = PersistentStore.save(context, describing: "That resolution")
    }

    private func acceptInvoice() {
        guard !isAccepting, let invoice else { return }
        // Asked again at the moment of the tap, not only at draw time. A finding can appear
        // between the two — the comparison is recomputed on every change to the store — and a
        // disabled-looking button is not a guarantee.
        guard case .success = InvoiceAcceptance.decide(acceptanceInput) else { return }

        isAccepting = true
        invoice.reviewStatusRaw = InvoiceReviewStatus.accepted.rawValue
        invoice.reviewedAt = dependencies.clock.now

        // The half that was missing. An accepted invoice closes the rental out: that is what
        // moves it off the Audit tab's "awaiting review" list, off Today's "invoices to review",
        // and into Resolved. Without it the user's tap changed a column nothing displayed.
        if let item {
            let workflow = RentalWorkflowService(context: context, clock: dependencies.clock)
            let resolved = workflow.apply(
                .resolve(openDiscrepancyCount: invoice.openDiscrepancyCount),
                to: item,
                detail: "Invoice \(invoice.invoiceNumber ?? "") accepted."
                    .trimmingCharacters(in: .whitespaces)
            )
            if case let .failure(failure) = resolved {
                // The state machine refused. Roll the invoice back rather than leaving it
                // accepted against a rental that is not resolved — two records disagreeing is
                // worse than one refusal the user can read.
                invoice.reviewStatusRaw = InvoiceReviewStatus.inReview.rawValue
                invoice.reviewedAt = nil
                isAccepting = false
                rejection = failure
                return
            }
        }

        if let problem = PersistentStore.save(context, describing: "This acceptance") {
            saveFailure = problem
            isAccepting = false
            return
        }
        saveFailure = nil
        // The rental has left Invoice review. Today's counts, the widget and the Shortcuts index
        // are all derived from its status, and the reminders it no longer needs are still
        // scheduled until this runs.
        dependencies.derivedStateNeedsRefresh()
        isAccepting = false
        withAnimation(Motion.respecting(Motion.quick, reduceMotion: reduceMotion)) {
            justAccepted = true
        }

        // Long enough to read the confirmation, short enough not to feel stuck. Going back is
        // the honest destination: this invoice is finished, and Audit is where the next one is.
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            // `dismiss`, not a pop of the Audit stack. This screen is reached from Today as
            // often as from Audit — Today's "Invoices to review" section links straight to it —
            // and the destination is appended to whichever tab's path the link was in. Popping
            // `auditPath` from a review opened on Today pops something else, or nothing.
            dismiss()
        }
    }
}
