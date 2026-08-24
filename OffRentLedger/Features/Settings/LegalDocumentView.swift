import SwiftUI

enum LegalDocument: String, Identifiable, CaseIterable {
    case privacy
    case terms

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacy: "Privacy Policy"
        case .terms: "Terms of Use"
        }
    }

    var resourceName: String {
        switch self {
        case .privacy: "PrivacyPolicy"
        case .terms: "TermsOfUse"
        }
    }

    var plannedURL: URL? {
        switch self {
        case .privacy: AppConfiguration.plannedPrivacyURL
        case .terms: AppConfiguration.plannedTermsURL
        }
    }
}

/// Renders the legal text that ships inside the app.
///
/// The text is bundled rather than fetched. A privacy policy behind a URL is a privacy policy that
/// 404s during App Review, disappears when a domain lapses, and cannot be read on a jobsite with
/// no signal. `AppConfiguration.legalURLsAreLive` is `false`, so nothing here presents a web
/// address as though it works.
struct LegalDocumentView: View {

    let document: LegalDocument
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.comfortable) {
                // On a card rather than straight onto the page. Two thousand words of legal text
                // with nothing behind it is the same blank-page problem the rest of this pass
                // fixed; the card gives the column an edge and a measure.
                Text(markdown)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offRentCard(padding: Space.roomy - 4)

                if AppConfiguration.legalURLsAreLive, let url = document.plannedURL {
                    Button("Read this online") { openURL(url) }
                        .buttonStyle(.offRentSecondary)
                }
            }
            .padding(.horizontal, Space.comfortable)
            .padding(.top, Space.base)
            .padding(.bottom, Space.screenBottom)
        }
        .offRentScreen()
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("legal.\(document.rawValue)")
    }

    /// The bundled text, rendered as Markdown.
    ///
    /// The fallback is not decoration. If the resource is somehow missing from the bundle, a
    /// screen saying "Privacy Policy" with nothing under it is an App Review rejection and a
    /// broken promise; a short honest message with a support address is neither.
    private var markdown: AttributedString {
        guard let url = Bundle.main.url(forResource: document.resourceName, withExtension: "md"),
              let raw = try? String(contentsOf: url, encoding: .utf8),
              let attributed = try? AttributedString(
                markdown: raw,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
              )
        else {
            return AttributedString(
                """
                This document could not be loaded from the app bundle. \
                Please contact \(AppConfiguration.supportEmail) and we will send it to you.
                """
            )
        }
        return attributed
    }
}

struct SupportView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                if let url = AppConfiguration.supportMailtoURL {
                    Button {
                        openURL(url)
                    } label: {
                        Label(AppConfiguration.supportEmail, systemImage: "envelope")
                    }
                    .minimumTapTarget()
                }
            } header: {
                Text("Get in touch")
            } footer: {
                Text("""
                    \(AppConfiguration.companyName). Tell us what you were doing and what happened \
                    — \(AppConfiguration.displayName) collects no diagnostics of its own, so your \
                    description is all we have to go on.
                    """)
            }

            Section("Common questions") {
                faq(
                    "Does \(AppConfiguration.displayName) contact my rental company?",
                    "No. It never has and it does not in this version. It helps you record what you did, reminds you to get a confirmation number, and keeps the evidence together. Calling the yard is still your job."
                )
                faq(
                    "Are the amounts what I owe?",
                    "No. They are estimates built from the rates and dates you entered. Your invoice and your rental agreement are what count."
                )
                faq(
                    "Does a possible mismatch mean I was overcharged?",
                    "No. It means the invoice differs from the terms you told the app about. That could be the vendor, your entry, or a term the app cannot see."
                )
                faq(
                    "Where is my data?",
                    "On this iPhone. There is no account and no server. If you delete the app without exporting first, it is gone."
                )
                faq(
                    "What happens if I cancel Pro?",
                    "Nothing you have is removed or hidden. You keep editing, resolving, exporting and deleting everything. You just cannot open a new rental beyond the free limit."
                )
            }
        }
        .offRentFormBackground()
        .navigationTitle("Support")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func faq(_ question: String, _ answer: String) -> some View {
        DisclosureGroup(question) {
            Text(answer)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
    }
}

struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppConfiguration.displayName).font(.title3.weight(.semibold))
                    Text("Version \(AppConfiguration.versionAndBuild)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                Text("""
                    Know what every equipment rental is costing, capture the vendor's off-rent \
                    confirmation, track pickup, and check the final invoice — across every rental \
                    yard.
                    """)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("What this is")
            }

            Section {
                Text(AppCopy.generalDisclaimer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(AppCopy.offRentDisclosure)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("What this is not")
            }

            Section {
                DetailRow(label: "Company", value: AppConfiguration.companyName)
                Text(AppConfiguration.poweredByLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Built with Apple's own frameworks. No third-party SDKs are included.")
            }
        }
        .offRentFormBackground()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
