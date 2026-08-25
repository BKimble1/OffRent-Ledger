import SwiftData
import SwiftUI

/// Creating a rental.
///
/// The manual path is the primary one and is complete on its own: no camera, no photo access, no
/// network, no account, no purchase. Scanning is an accelerator that fills the same draft, and it
/// always lands in the review sheet before touching anything here.
///
/// Everything a user can type lives in `RentalFormView`, shared with Edit Rental. This screen is
/// the create half: a save bar, and the one piece of work that only creation does — turning a
/// draft into a company, an agreement and an item, in that order.
struct AddRentalView: View {

    /// Opens the scanner as the screen appears, for the entry point on Today.
    ///
    /// The scan is the accelerator, not a second way to create a rental: it fills this same draft
    /// and lands in the same review sheet, and cancelling the camera leaves an ordinary empty New
    /// Rental form rather than dead-ending.
    var startScanning: Bool = false

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Vendor.name) private var companies: [Vendor]
    @Query(sort: \JobSite.name) private var jobSites: [JobSite]

    @State private var draft = RentalDraft()
    @State private var isSaving = false
    @State private var hasPrepared = false
    @State private var saveFailure: String?

    var body: some View {
        NavigationStack {
            RentalFormView(draft: draft, startScanning: startScanning)
                .accessibilityIdentifier(A11yID.AddRental.root)
                .safeAreaInset(edge: .bottom) { saveBar }
                .navigationTitle("New rental")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .accessibilityIdentifier(A11yID.AddRental.cancel)
                    }
                }
                .onAppear {
                    guard !hasPrepared else { return }
                    hasPrepared = true
                    draft.deliveryDate = dependencies.clock.now
                    // If there is exactly one company, it is the one. A contractor with a single
                    // rental yard should not pick it every time; anybody with two is asked.
                    if draft.companyID == nil, companies.count == 1 {
                        draft.companyID = companies.first?.id
                    }
                }
        }
    }

    /// Save, where the thumb is, on a form seven sections long.
    ///
    /// One primary action rather than a `Save` in the navigation bar: the last field is a long
    /// way from the top, and a disabled toolbar button gives no clue what is missing. This one
    /// says, in words, which field.
    private var saveBar: some View {
        StickyActionBar {
            VStack(spacing: Space.snug) {
                Button("Save rental", action: save)
                    .buttonStyle(.offRentPrimary)
                    .accessibilityIdentifier(A11yID.AddRental.save)
                    .disabled(!draft.canSave || isSaving)
                if let missing = draft.missingRequirement {
                    Text(missing)
                        .font(Typography.micro)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(A11yID.AddRental.missingRequirement)
                }
                if let saveFailure {
                    Text(saveFailure)
                        .font(Typography.micro)
                        .foregroundStyle(Palette.attentionText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Saving

    private func save() {
        // Guards a double tap. Without it a slow save can insert the rental twice, and the free
        // tier then reports a limit the user did not reach.
        guard !isSaving, draft.canSave else { return }
        guard let companyID = draft.companyID,
              let vendor = companies.first(where: { $0.id == companyID })
        else { return }
        isSaving = true
        defer { isSaving = false }

        let now = dependencies.clock.now
        let site: JobSite? = draft.jobSiteID.flatMap { id in jobSites.first { $0.id == id } }

        let agreement = RentalAgreement(
            agreementNumber: draft.agreementNumber.nilIfBlank,
            purchaseOrderNumber: draft.purchaseOrderNumber.nilIfBlank,
            startDate: draft.deliveryDate,
            scheduledEndDate: draft.scheduledEndDate,
            notes: nil,
            createdAt: now,
            modifiedAt: now,
            vendor: vendor,
            jobSite: site
        )
        context.insert(agreement)

        let workflow = RentalWorkflowService(context: context, clock: dependencies.clock)
        workflow.createItem(
            equipmentName: draft.trimmedEquipmentName,
            equipmentClass: draft.equipmentClass.nilIfBlank,
            vendorEquipmentIdentifier: draft.vendorEquipmentIdentifier.nilIfBlank,
            serialNumber: draft.serialNumber.nilIfBlank,
            terms: draft.terms(),
            meterUnit: draft.meterUnit,
            notes: draft.notes.nilIfBlank,
            in: agreement
        )

        // Dismissing before the write is confirmed would show the contractor a rental that
        // is not in the ledger. Stay on the form and say so instead.
        if let problem = PersistentStore.save(context, describing: "This rental") {
            // Take the insert back before inviting a retry. `context.insert` puts the record in
            // the context whether or not the save lands, so a second tap on Save inserted a
            // second one — and the message on screen is asking for exactly that second tap.
            context.rollback()
            saveFailure = problem
            isSaving = false
            return
        }
        saveFailure = nil
        // The estimate, the widget, the Shortcuts index and the reminder for this rental's
        // scheduled end are all derived. Without this they wait for the next foreground.
        dependencies.derivedStateNeedsRefresh()
        dismiss()
    }
}

/// A date picker that can genuinely be empty. `DatePicker` cannot, and defaulting a blank
/// "scheduled end" to today would put a date on the record the user never gave.
struct OptionalDatePicker: View {
    let title: String
    @Binding var date: Date?
    var identifier: String?

    var body: some View {
        VStack(alignment: .leading) {
            Toggle(title, isOn: Binding(
                get: { date != nil },
                set: { date = $0 ? (date ?? Date()) : nil }
            ))
            .minimumTapTarget()

            if date != nil {
                DatePicker(
                    title,
                    selection: Binding(get: { date ?? Date() }, set: { date = $0 }),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .accessibilityIdentifier(identifier ?? "optionalDate.\(title)")
            }
        }
    }
}

extension String {
    /// nil rather than "". A stored empty string reads as "the user entered nothing here", which
    /// is not the same as "the user left it blank" once it reaches an export or a PDF.
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
