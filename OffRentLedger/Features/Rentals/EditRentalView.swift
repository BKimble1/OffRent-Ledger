import SwiftData
import SwiftUI

/// Editing a rental — all of it.
///
/// What was there before could reach four fields: equipment name, class, the three rates and the
/// notes. A rental filed under the wrong company stayed there. A rental with no jobsite could
/// never be put on the map. An agreement number typed into the serial field was permanent.
///
/// This uses the same `RentalFormView` as New Rental, so "everything you can enter, you can
/// correct" is a property of there being one form rather than a list somebody maintains.
///
/// What it deliberately does *not* touch:
///
/// - **Status.** Only `RentalWorkflowService` assigns it, and `verify_repository.py` fails the
///   build if anything else tries.
/// - **Timeline events.** Confirmation and pickup are records of things that happened at a time.
///   Correcting a daily rate must not silently rewrite what the yard told somebody on a Tuesday.
/// - **Attached invoices and scan evidence.** They belong to the agreement, and editing the
///   rental's metadata leaves them exactly where they are.
///
/// A wrong confirmation is corrected through Reopen, which asks for a reason and writes its own
/// event — because changing what a vendor said is a different act from fixing a typo.
struct EditRentalView: View {

    let itemID: UUID

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var items: [RentalItem]
    @Query(sort: \Vendor.name) private var companies: [Vendor]
    @Query(sort: \JobSite.name) private var jobSites: [JobSite]

    @State private var draft = RentalDraft()
    @State private var hasLoaded = false
    @State private var isSaving = false
    @State private var saveFailure: String?

    init(itemID: UUID) {
        self.itemID = itemID
        _items = Query(filter: #Predicate<RentalItem> { $0.id == itemID })
    }

    private var item: RentalItem? { items.first }

    var body: some View {
        Group {
            if item != nil {
                // The identifier goes on the form, *before* the inset — the same order
                // `AddRentalView` uses, and for a reason CI showed rather than argued.
                //
                // It used to sit on this `Group`, which wraps the form and the save bar
                // together. An accessibility modifier applied over a `safeAreaInset` is pushed
                // down into the inset's contents, so `editRental.root` landed on the Save button
                // as well and replaced `editRental.save`. The dump is unambiguous:
                // `Button, identifier: 'editRental.root', label: 'Save changes'`. The test
                // waited eight seconds for a button that was on screen, enabled, and renamed.
                RentalFormView(draft: draft, showsCapture: false)
                    .accessibilityIdentifier(A11yID.EditRental.root)
                    .safeAreaInset(edge: .bottom) { saveBar }
            } else {
                EmptyStateView(
                    symbol: "questionmark.folder",
                    title: "That rental is gone",
                    message: "It was deleted, or the backup it came from no longer has it."
                )
                .accessibilityIdentifier(A11yID.EditRental.root)
            }
        }
        .navigationTitle("Edit rental")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private var saveBar: some View {
        StickyActionBar {
            VStack(spacing: Space.snug) {
                Button("Save changes", action: save)
                    .buttonStyle(.offRentPrimary)
                    .disabled(!draft.canSave || isSaving)
                    .accessibilityIdentifier(A11yID.EditRental.save)
                if let missing = draft.missingRequirement {
                    Text(missing)
                        .font(Typography.micro)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let note = historyNote {
                    Text(note)
                        .font(Typography.micro)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
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

    /// Says what this screen will not change, and what it will change beyond this one rental.
    private var historyNote: String? {
        // The sharing note first: it is the surprising one. An agreement carrying two machines
        // is one piece of paper, so the company, the jobsite, the dates and the reference
        // numbers belong to both — and changing them here changes them for both. New Rental
        // always makes a fresh agreement, so this only arises for an imported backup, but a
        // silent edit to a rental the user is not looking at is not something to leave unsaid.
        if let siblings = item?.agreement?.items?.count, siblings > 1 {
            let others = siblings - 1
            return """
                This rental shares its agreement with \(others) other\(others == 1 ? "" : "s"). \
                The company, jobsite, dates and reference numbers are on the agreement, so \
                changing them here changes them there too.
                """
        }
        guard let item, item.status.order > RentalItemStatus.active.order else { return nil }
        return """
            Your confirmation, pickup and any attached invoice are kept as they are. Use Reopen \
            on the rental if one of those needs correcting.
            """
    }

    // MARK: - Loading and saving

    private func load() {
        guard !hasLoaded, let item else { return }
        hasLoaded = true
        draft.load(from: item)
    }

    private func save() {
        guard !isSaving, draft.canSave, let item else { return }
        guard let companyID = draft.companyID,
              let vendor = companies.first(where: { $0.id == companyID })
        else { return }
        isSaving = true
        defer { isSaving = false }

        let now = dependencies.clock.now
        let site: JobSite? = draft.jobSiteID.flatMap { id in jobSites.first { $0.id == id } }

        // The agreement is where the company, jobsite, dates and references live. An item always
        // has one — `createItem` requires it — but the optional is honoured rather than forced.
        if let agreement = item.agreement {
            agreement.vendor = vendor
            agreement.jobSite = site
            agreement.agreementNumber = draft.agreementNumber.nilIfBlank
            agreement.purchaseOrderNumber = draft.purchaseOrderNumber.nilIfBlank
            agreement.startDate = draft.deliveryDate
            agreement.scheduledEndDate = draft.scheduledEndDate
            agreement.modifiedAt = now
        }

        item.equipmentName = draft.trimmedEquipmentName
        item.equipmentClass = draft.equipmentClass.nilIfBlank
        item.vendorEquipmentIdentifier = draft.vendorEquipmentIdentifier.nilIfBlank
        item.serialNumber = draft.serialNumber.nilIfBlank
        item.meterUnitRaw = draft.meterUnit.rawValue
        item.notes = draft.notes.nilIfBlank
        // `preserving:` carries `accrualStoppedAt` and the rollover override across the write.
        // Without it, correcting a rate on a rental that is already off rent would start its
        // estimate running again — the one number this app exists to stop.
        item.terms = draft.terms(preserving: item.terms)
        item.modifiedAt = now

        // Everything downstream of a rental is derived, so it is all recomputed rather than left
        // to drift until the next launch: the cached estimate here, and the widget snapshot, the
        // map annotations, the search index and the reminders on the next `refresh()`.
        RentalWorkflowService(context: context, clock: dependencies.clock).refreshEstimate(for: item)
        if let problem = PersistentStore.save(context, describing: "Your changes") {
            saveFailure = problem
            isSaving = false
            return
        }
        saveFailure = nil
        // §9: an edit reaches the reminders. A changed scheduled end date is the case that
        // matters — the old reminder is for a day that is no longer the day.
        dependencies.derivedStateNeedsRefresh()
        dismiss()
    }
}
