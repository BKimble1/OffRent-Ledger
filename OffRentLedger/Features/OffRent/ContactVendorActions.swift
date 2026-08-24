import SwiftData
import SwiftUI

/// The Contact Vendor state's actions.
///
/// Every one of them hands the user off to something they drive themselves — the phone app, a
/// mail draft, the vendor's own site. None of them sends anything. "Record a contact attempt"
/// deliberately does not advance the workflow: trying the yard and getting voicemail leaves the
/// item exactly where it was, which is the honest state.
struct ContactVendorActions: View {

    let item: RentalItem

    @Environment(AppDependencies.self) private var dependencies
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL

    @State private var showingAttemptSheet = false
    @State private var attemptMethod: VendorContactMethod = .phone
    @State private var attemptRepresentative = ""
    @State private var attemptNote = ""

    private var vendor: Vendor? { item.agreement?.vendor }

    var body: some View {
        // Plain rows: this sits inside an inset-grouped `Section` on the detail screen, so the
        // list draws the surface, the separators and the tap highlight.
        Group {
            if let phone = vendor?.phone, let url = telURL(phone) {
                Button {
                    openURL(url)
                    // Opening the dialler is recorded as an *attempt*, because that is all the
                    // app can observe. Whether anybody answered is something only the user knows.
                    recordAttempt(
                        method: .phone,
                        note: "Opened the dialler from \(AppConfiguration.displayName)."
                    )
                } label: {
                    Label("Call \(vendor?.name ?? "the rental company")", systemImage: "phone")
                }
                .accessibilityIdentifier(A11yID.ContactVendor.call)
            }

            if let email = vendor?.email, let url = mailtoURL(email) {
                Button {
                    openURL(url)
                    recordAttempt(
                        method: .email,
                        note: "Opened an email draft from \(AppConfiguration.displayName)."
                    )
                } label: {
                    Label("Email the rental company", systemImage: "envelope")
                }
                .accessibilityIdentifier(A11yID.ContactVendor.email)
            }

            if let link = vendor?.link, let url = URL(string: link), url.scheme != nil {
                Button {
                    openURL(url)
                    recordAttempt(method: .vendorWebsite, note: "Opened the vendor link.")
                } label: {
                    Label("Open the vendor's site", systemImage: "safari")
                }
                .accessibilityIdentifier(A11yID.ContactVendor.openLink)
            }

            Button {
                showingAttemptSheet = true
            } label: {
                Label("Record a contact attempt", systemImage: "phone.arrow.up.right")
            }
            .accessibilityIdentifier(A11yID.ContactVendor.logAttempt)
            .accessibilityHint("Adds a timeline entry. It does not change the status of this rental.")

            Button {
                router.presentedSheet = .recordConfirmation(itemID: item.id)
            } label: {
                Label("Record the vendor's confirmation", systemImage: "checkmark.rectangle.stack")
            }
            .accessibilityIdentifier(A11yID.ContactVendor.recordConfirmation)

            if vendor?.phone == nil, vendor?.email == nil, vendor?.link == nil {
                Text("""
                    No phone, email or link is saved for this rental company. Add one on the \
                    vendor's page to reach it from here.
                    """)
                    .font(Typography.rowDetail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: $showingAttemptSheet) { attemptSheet }
    }

    private var attemptSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("How did you try?", selection: $attemptMethod) {
                        ForEach(VendorContactMethod.allCases, id: \.self) { method in
                            Label(method.displayName, systemImage: method.symbolName).tag(method)
                        }
                    }
                    TextField("Who did you speak to? (optional)", text: $attemptRepresentative)
                    TextField("What happened?", text: $attemptNote, axis: .vertical)
                        .lineLimit(2...5)
                } footer: {
                    Text("""
                        This adds a line to the timeline. It does not move the rental forward — \
                        record the vendor's confirmation separately once you have it.
                        """)
                }
            }
            .offRentFormBackground()
            .navigationTitle("Contact attempt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingAttemptSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        recordAttempt(
                            method: attemptMethod,
                            representative: attemptRepresentative.isEmpty ? nil : attemptRepresentative,
                            note: attemptNote.isEmpty ? nil : attemptNote
                        )
                        attemptRepresentative = ""
                        attemptNote = ""
                        showingAttemptSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func recordAttempt(
        method: VendorContactMethod, representative: String? = nil, note: String? = nil
    ) {
        let workflow = RentalWorkflowService(context: context, clock: dependencies.clock)
        workflow.recordContactAttempt(
            method: method, representative: representative, note: note, for: item
        )
        try? context.save()
    }

    private func telURL(_ phone: String) -> URL? {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel://\(digits)")
    }

    private func mailtoURL(_ email: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        // Built as explicit locals rather than inline in the interpolation.
        //
        // `jobSite?.name` is a *non-optional* String reached through an optional chain, so
        // `.name.map { }` binds to `Sequence.map` — mapping over the characters — and yields
        // `[String]?`, not `String?`. It reads identically to the optional-map two lines above
        // it and means something completely different. Naming the intermediate values makes the
        // type obvious at the declaration instead of hiding it inside a string.
        let agreementSuffix: String =
            item.agreement?.agreementNumber.map { " (agreement \($0))" } ?? ""
        let unitLine: String =
            item.vendorEquipmentIdentifier.map { "Unit: \($0)\n" } ?? ""
        let agreementLine: String =
            item.agreement?.agreementNumber.map { "Agreement: \($0)\n" } ?? ""

        let jobSite: JobSite? = item.agreement?.jobSite
        let jobSiteLine: String = jobSite.map { "Jobsite: \($0.name)\n" } ?? ""

        let body = """
            Please take the following equipment off rent and send a confirmation number.

            Equipment: \(item.equipmentName)
            \(unitLine)\(agreementLine)\(jobSiteLine)
            Thank you.
            """

        components.queryItems = [
            URLQueryItem(
                name: "subject",
                value: "Off-rent request: \(item.equipmentName)\(agreementSuffix)"
            ),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }
}
