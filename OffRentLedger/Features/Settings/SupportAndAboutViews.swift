import SwiftUI
import UIKit

/// Support, laid out as somewhere to get an answer rather than a list of paragraphs.
///
/// Two things a support screen has to do: get somebody to a human quickly, and answer the
/// questions that bring most people here before they need one. So contact is at the top, the
/// questions are searchable, and the details that a support reply always has to ask for —
/// version, build, iOS, hardware — are gathered in one place with a Copy button.
///
/// Nothing here is collected or sent anywhere on its own. The app has no analytics and no
/// crash reporter, which is exactly why the user has to be able to hand those details over.
struct SupportView: View {

    @Environment(\.openURL) private var openURL
    @State private var query = ""
    @State private var copiedDiagnostics = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                contact
                questions
                diagnostics
            }
            .padding(.horizontal, Space.comfortable)
            .padding(.top, Space.base)
            .padding(.bottom, Space.screenBottom)
        }
        .offRentScreen()
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(A11yID.Settings.supportRoot)
    }

    // MARK: - Contact

    private var contact: some View {
        VStack(alignment: .leading, spacing: Space.base) {
            CardHeader(
                title: "Talk to a person",
                subtitle: """
                    Tell us what you were doing and what happened. \
                    \(AppConfiguration.displayName) collects no diagnostics of its own, so your \
                    description is all we have to go on.
                    """
            )

            if let mail = AppConfiguration.supportMailtoURL {
                Button {
                    openURL(mail)
                } label: {
                    Label("Email \(AppConfiguration.supportEmail)", systemImage: "envelope")
                }
                .buttonStyle(.offRentPrimary)
                .accessibilityIdentifier(A11yID.Settings.supportEmail)
            }

            if let site = AppConfiguration.plannedSupportURL {
                Button {
                    openURL(site)
                } label: {
                    Label("Open the help site", systemImage: "safari")
                }
                .buttonStyle(.offRentSecondary)
                .accessibilityIdentifier(A11yID.Settings.supportWebsite)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offRentCard()
    }

    // MARK: - Questions

    private var questions: some View {
        VStack(alignment: .leading, spacing: Space.base) {
            CardHeader(title: "Common questions")

            HStack(spacing: Space.snug) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search questions", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier(A11yID.Settings.supportSearch)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .accessibilityLabel("Clear the search")
                }
            }
            .padding(.horizontal, Space.base)
            .frame(height: Layout.controlHeight)
            .background(Palette.sunken, in: RoundedRectangle(cornerRadius: Radius.control))

            if matches.isEmpty {
                Text("""
                    Nothing here matches "\(query)". Email us and we will answer it — and \
                    probably add it to this list.
                    """)
                    .font(Typography.rowDetail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Space.tight)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.element.question) { index, item in
                        if index > 0 { RowDivider(inset: 0) }
                        DisclosureGroup {
                            Text(item.answer)
                                .font(Typography.rowDetail)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, Space.tight)
                                .padding(.bottom, Space.snug)
                        } label: {
                            Text(item.question)
                                .font(Typography.rowTitle)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, Space.snug)
                        }
                        .tint(Palette.accent)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offRentCard()
    }

    private var matches: [SupportQuestion] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return SupportQuestion.all }
        return SupportQuestion.all.filter { $0.matches(trimmed) }
    }

    // MARK: - Diagnostics

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: Space.base) {
            CardHeader(
                title: "Details to include",
                subtitle: "Paste these into your email. Nothing is sent unless you send it."
            )

            VStack(spacing: 0) {
                ForEach(Array(DiagnosticsReport.current.rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { RowDivider(inset: 0) }
                    DetailRow(label: row.label, value: row.value)
                }
            }

            Button {
                UIPasteboard.general.string = DiagnosticsReport.current.plainText
                copiedDiagnostics = true
            } label: {
                Label(
                    copiedDiagnostics ? "Copied" : "Copy these details",
                    systemImage: copiedDiagnostics ? "checkmark" : "doc.on.doc"
                )
            }
            .buttonStyle(.offRentSecondary)
            .accessibilityIdentifier(A11yID.Settings.copyDiagnostics)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offRentCard()
    }
}

/// One question and its answer.
///
/// Kept as data rather than as a stack of views so the search filter is one `filter` call and
/// so the wording lives beside the rest of the product's copy rules.
struct SupportQuestion {
    let question: String
    let answer: String

    func matches(_ needle: String) -> Bool {
        question.localizedCaseInsensitiveContains(needle)
            || answer.localizedCaseInsensitiveContains(needle)
    }

    static let all: [SupportQuestion] = [
        SupportQuestion(
            question: "Does \(AppConfiguration.displayName) contact my rental company?",
            answer: """
                No. It never has and it does not in this version. It helps you record what you \
                did, reminds you to get a confirmation number, and keeps the evidence together. \
                Calling the yard is still your job.
                """
        ),
        SupportQuestion(
            question: "Are the amounts what I owe?",
            answer: """
                No. They are estimates built from the rates and dates you entered. Your invoice \
                and your rental agreement are what count.
                """
        ),
        SupportQuestion(
            question: "Does a possible mismatch mean I was overcharged?",
            answer: """
                No. It means the invoice differs from the terms you told the app about. That \
                could be the vendor, your entry, or a term the app cannot see.
                """
        ),
        SupportQuestion(
            question: "Where is my data?",
            answer: """
                On this iPhone. There is no account and no server. Back it up from Settings \
                before you change phones or delete the app.
                """
        ),
        SupportQuestion(
            question: "How do I move everything to a new iPhone?",
            answer: """
                Settings › Backup and transfer › Export a full backup, then open that file on \
                the new phone and import it. The archive carries rentals, vendors, job sites, \
                confirmations, pickups and invoices.
                """
        ),
        SupportQuestion(
            question: "Why did a reminder not arrive?",
            answer: """
                Either notifications are switched off for the app, the reminder is outside the \
                quiet hours you set, or the rental has no date to remind you about. Settings › \
                Reminders shows the permission state and everything currently scheduled.
                """
        ),
        SupportQuestion(
            question: "Scanning read my agreement wrong. What now?",
            answer: """
                Nothing is saved from a scan until you tap Save on the review screen, and every \
                field can be edited or switched off there. If a document reads badly every time, \
                send us a photo of it.
                """
        ),
        SupportQuestion(
            question: "What happens if I cancel Pro?",
            answer: """
                Nothing you have is removed or hidden. You keep editing, resolving, exporting \
                and deleting everything. You just cannot open a new rental beyond the free limit.
                """
        ),
    ]
}

/// The facts a support reply always ends up asking for.
struct DiagnosticsReport {
    struct Row {
        let label: String
        let value: String
    }

    let rows: [Row]

    var plainText: String {
        rows.map { "\($0.label): \($0.value)" }.joined(separator: "\n")
    }

    static var current: DiagnosticsReport {
        DiagnosticsReport(rows: [
            Row(label: AppConfiguration.displayName, value: AppConfiguration.versionAndBuild),
            Row(label: "iOS", value: UIDevice.current.systemVersion),
            Row(label: "Device", value: hardwareIdentifier),
        ])
    }

    /// "iPhone17,1" rather than "iPhone". The marketing name is not available to an app, and the
    /// identifier is what actually tells support which hardware this is.
    static var hardwareIdentifier: String {
        var info = utsname()
        uname(&info)
        let identifier = Mirror(reflecting: info.machine).children
            .reduce(into: "") { result, element in
                guard let byte = element.value as? Int8, byte != 0 else { return }
                result.append(Character(UnicodeScalar(UInt8(bitPattern: byte))))
            }
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }
}

/// About: what this app is, what it is not, and where to find the rest.
struct AboutView: View {

    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.section) {
                identity
                whatItIs
                whatItIsNot
                links
                credits
            }
            .padding(.horizontal, Space.comfortable)
            .padding(.top, Space.base)
            .padding(.bottom, Space.screenBottom)
        }
        .offRentScreen()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(A11yID.Settings.aboutRoot)
    }

    private var identity: some View {
        HStack(spacing: Space.comfortable) {
            Image("LaunchMark")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(AppConfiguration.displayName)
                    .font(.title3.weight(.semibold))
                Text("Version \(AppConfiguration.versionAndBuild)")
                    .font(Typography.rowDetail)
                    .foregroundStyle(.secondary)
                Text(AppConfiguration.poweredByLine)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .offRentCard()
    }

    private var whatItIs: some View {
        VStack(alignment: .leading, spacing: Space.snug) {
            CardHeader(title: "What this is")
            Text("""
                Know what every equipment rental is costing, capture the vendor's off-rent \
                confirmation, track pickup, and check the final invoice — across every rental \
                yard.
                """)
                .font(Typography.rowDetail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offRentCard()
    }

    private var whatItIsNot: some View {
        VStack(alignment: .leading, spacing: Space.base) {
            CardHeader(title: "What this is not", symbol: "exclamationmark.bubble", tint: Palette.attention)
            Text(AppCopy.generalDisclaimer)
                .font(Typography.rowDetail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(AppCopy.offRentDisclosure)
                .font(Typography.rowDetail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offRentCard()
    }

    private var links: some View {
        ListGroup {
            if let site = AppConfiguration.plannedWebsiteURL {
                ActionRow(
                    title: "offrent.idlery.com",
                    subtitle: "The product site",
                    symbol: "safari",
                    opensExternally: true
                ) { openURL(site) }
                    .accessibilityIdentifier(A11yID.Settings.aboutWebsite)
                RowDivider()
            }
            NavigationLink(value: SettingsDestination.privacyPolicy) {
                NavigationRow(title: "Privacy Policy", symbol: "hand.raised")
            }
            .buttonStyle(.plain)
            RowDivider()
            NavigationLink(value: SettingsDestination.terms) {
                NavigationRow(title: "Terms of Use", symbol: "doc.text")
            }
            .buttonStyle(.plain)
            RowDivider()
            NavigationLink(value: SettingsDestination.support) {
                NavigationRow(title: "Support", symbol: "questionmark.circle")
            }
            .buttonStyle(.plain)
        }
    }

    private var credits: some View {
        VStack(alignment: .leading, spacing: Space.snug) {
            CardHeader(title: "How it is built")
            DetailRow(label: "Company", value: AppConfiguration.companyName)
            RowDivider(inset: 0)
            Text("""
                Apple's own frameworks only. No third-party SDKs, no analytics, no advertising \
                identifiers, no account, and no server of ours that your records pass through.
                """)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.tight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offRentCard()
    }
}

#Preview("Support") {
    NavigationStack { SupportView() }
}

#Preview("About") {
    NavigationStack { AboutView() }
}
