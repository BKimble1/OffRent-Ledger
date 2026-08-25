import SwiftData
import SwiftUI

/// The one rental-company form.
///
/// Reached from three places — the Rentals plus menu, `Add New` inside a rental draft, and the
/// company list — and it is the same screen in all three. Before this there were two: a full
/// editor on the company list and an ad-hoc set of four text fields inlined into New Rental,
/// which is why a company created while adding a rental had no website, no notes and no way to
/// gain them without going somewhere else.
///
/// `onSaved` is what makes it reusable from inside a draft. The caller gets the record back and
/// decides what to do with it; the editor itself knows nothing about rentals.
struct CompanyEditorView: View {

    /// The company being edited, or nil to create one.
    let existing: Vendor?
    /// Pre-fills the name when the user typed a search that matched nothing.
    var initialName: String = ""
    var onSaved: (Vendor) -> Void = { _ in }

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Vendor.name) private var allCompanies: [Vendor]

    @State private var name = ""
    @State private var branch = ""
    @State private var contactName = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var address = ""
    @State private var link = ""
    @State private var notes = ""
    @State private var duplicate: Vendor?
    @State private var hasLoaded = false
    @State private var saveFailure: String?
    @FocusState private var nameIsFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Company name", text: $name)
                        .textContentType(.organizationName)
                        .focused($nameIsFocused)
                        .accessibilityIdentifier(A11yID.Company.name)
                    TextField("Branch or yard (optional)", text: $branch)
                        .accessibilityIdentifier(A11yID.Company.branch)
                } header: {
                    Text("Company")
                } footer: {
                    if let duplicate {
                        // Named, not merely refused. "That already exists" with no way to see it
                        // is a dead end; this is a way through.
                        Text("""
                            You already have \(duplicate.name)\
                            \(duplicate.branch.map { " · \($0)" } ?? ""). \
                            Use that one instead, or give this a different branch.
                            """)
                            .foregroundStyle(Palette.attentionText)
                    } else {
                        Text("Only the name is required. Everything else can wait.")
                    }
                }

                Section("Who you deal with") {
                    TextField("Contact name (optional)", text: $contactName)
                        .textContentType(.name)
                        .accessibilityIdentifier(A11yID.Company.contact)
                    TextField("Phone (optional)", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .accessibilityIdentifier(A11yID.Company.phone)
                    TextField("Email (optional)", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier(A11yID.Company.email)
                    if !emailIsPlausible {
                        Text("That does not look like an email address.")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.attentionText)
                    }
                }

                Section {
                    TextField("Street or mailing address (optional)", text: $address, axis: .vertical)
                        .lineLimit(1...3)
                        .textContentType(.fullStreetAddress)
                        .accessibilityIdentifier(A11yID.Company.address)
                    TextField("Website or app link (optional)", text: $link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Where they are")
                } footer: {
                    Text("""
                        The phone, email and link become the Call, Email and Open-link buttons on \
                        the Contact Vendor step. \(AppConfiguration.displayName) opens them for \
                        you — it never sends anything itself.
                        """)
                }

                Section("Notes") {
                    TextField("Anything you want on hand", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                if let saveFailure {
                    Section {
                        Label(saveFailure, systemImage: "externaldrive.badge.exclamationmark")
                            .foregroundStyle(Palette.attentionText)
                    }
                }
            }
            .offRentFormBackground()
            .navigationTitle(existing == nil ? "New rental company" : "Rental company")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier(A11yID.Company.cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                        .accessibilityIdentifier(A11yID.Company.save)
                }
            }
            .onAppear(perform: load)
            .onChange(of: name) { _, _ in refreshDuplicate() }
            .onChange(of: branch) { _, _ in refreshDuplicate() }
        }
        .accessibilityIdentifier(A11yID.Company.root)
    }

    // MARK: - State

    private var canSave: Bool {
        CompanyMatching.isUsableName(name) && duplicate == nil && emailIsPlausible
    }

    private var emailIsPlausible: Bool { EmailValidation.isPlausible(email) }

    private func load() {
        // `.onAppear` fires again when a nested sheet closes over this one; reloading then would
        // throw away everything the user has typed.
        guard !hasLoaded else { return }
        hasLoaded = true
        if let existing {
            name = existing.name
            branch = existing.branch ?? ""
            contactName = existing.contactName ?? ""
            phone = existing.phone ?? ""
            email = existing.email ?? ""
            address = existing.address ?? ""
            link = existing.link ?? ""
            notes = existing.standardNotes ?? ""
        } else {
            name = initialName
            nameIsFocused = name.isEmpty
        }
        refreshDuplicate()
    }

    private func refreshDuplicate() {
        let identities = allCompanies.map {
            CompanyIdentity(id: $0.id, name: $0.name, branch: $0.branch)
        }
        let match = CompanyMatching.duplicate(
            ofName: name, branch: branch, in: identities, excluding: existing?.id
        )
        duplicate = match.flatMap { found in allCompanies.first { $0.id == found.id } }
    }

    private func save() {
        guard canSave else { return }
        let now = dependencies.clock.now
        let company: Vendor
        if let existing {
            company = existing
        } else {
            company = Vendor(name: "", createdAt: now, modifiedAt: now)
            context.insert(company)
        }
        company.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        company.branch = branch.nilIfBlank
        company.contactName = contactName.nilIfBlank
        company.phone = phone.nilIfBlank
        company.email = email.nilIfBlank
        company.address = address.nilIfBlank
        company.link = link.nilIfBlank
        company.standardNotes = notes.nilIfBlank
        company.modifiedAt = now
        if let problem = PersistentStore.save(context, describing: "This company") {
            saveFailure = problem
            return
        }
        saveFailure = nil
        onSaved(company)
        dismiss()
    }
}

/// Pick a company, or make one.
///
/// A searchable list rather than a `Picker`. A wheel with forty rental yards in it is unusable,
/// and the old inline form meant `New rental company` was the *first* option in the picker —
/// so the default action on a screen full of existing companies was to create another.
struct CompanyPickerView: View {

    @Binding var selection: UUID?
    /// Seeds the search field. Set when a scan read a company name off a letterhead: the app
    /// will not create that record on the user's behalf, but it can save them typing it.
    var initialSearch: String = ""
    /// Called after a pick or a creation, so a rental draft can close the sheet itself.
    var onPicked: (Vendor) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Vendor.name) private var companies: [Vendor]

    @State private var search = ""
    @State private var creating = false
    /// A company created by the nested editor, held until that editor has actually closed.
    ///
    /// Dismissing this picker from inside `onSaved` would be dismissing a sheet while its own
    /// child sheet is still on screen. SwiftUI does not reliably unwind two presentations in one
    /// turn of the run loop, and the failure mode is the worst one available here — the editor
    /// closes, the picker stays, and the rental draft underneath is never reached.
    @State private var pendingPick: Vendor?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        creating = true
                    } label: {
                        Label("Add a new rental company", systemImage: "plus.circle.fill")
                            .foregroundStyle(Palette.accentText)
                    }
                    .accessibilityIdentifier(A11yID.Company.addNew)
                }

                if filtered.isEmpty {
                    Section {
                        Text(
                            companies.isEmpty
                                ? "No rental companies yet. Add the yard you are renting from."
                                : "No company matches “\(search)”."
                        )
                        .font(Typography.rowDetail)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(filtered, id: \.id) { company in
                            Button { pick(company) } label: { row(company) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier(A11yID.Company.row(company.id))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .offRentFormBackground()
            .searchable(text: $search, prompt: "Company or branch")
            .navigationTitle("Rental company")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if search.isEmpty { search = initialSearch }
            }
            .sheet(isPresented: $creating) {
                // Saving from here selects the new company and closes *both* sheets, so somebody
                // who came from a half-filled rental lands back on it with the company set.
                CompanyEditorView(existing: nil, initialName: search) { created in
                    pendingPick = created
                }
            }
            .onChange(of: creating) { _, isCreating in
                guard !isCreating, let created = pendingPick else { return }
                pendingPick = nil
                pick(created)
            }
        }
        .accessibilityIdentifier(A11yID.Company.pickerRoot)
    }

    private func row(_ company: Vendor) -> some View {
        HStack(spacing: Space.base) {
            RowIcon(symbol: "building.2")
            VStack(alignment: .leading, spacing: 1) {
                Text(company.name).font(Typography.rowTitle).foregroundStyle(.primary)
                if let detail = detail(company) {
                    Text(detail)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Space.snug)
            if selection == company.id {
                Image(systemName: "checkmark")
                    .font(Typography.rowDetail.weight(.semibold))
                    .foregroundStyle(Palette.accentText)
            }
        }
        .contentShape(Rectangle())
        .minimumTapTarget()
    }

    private func detail(_ company: Vendor) -> String? {
        [company.branch, company.contactName, company.phone]
            .compactMap { $0 }
            .first
    }

    private func pick(_ company: Vendor) {
        selection = company.id
        onPicked(company)
        dismiss()
    }

    private var filtered: [Vendor] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return companies }
        return companies.filter { company in
            let fields: [String?] = [company.name, company.branch, company.contactName]
            let haystack: String = fields.compactMap { $0 }.joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(query)
        }
    }
}
