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

    /// One line saying what the document is for, above the clauses.
    var summary: String {
        switch self {
        case .privacy:
            """
            Short version: your records stay on this iPhone. There is no account, no server and \
            no analytics. The long version is below.
            """
        case .terms:
            """
            Short version: this app keeps your records. It does not contact rental companies, \
            end rentals, or decide what you owe. The long version is below.
            """
        }
    }
}

/// The legal text that ships inside the app, laid out as a document rather than dumped as one
/// block of Markdown.
///
/// The text is bundled rather than fetched. A privacy policy behind a URL is a privacy policy
/// that 404s during App Review, disappears when a domain lapses, and cannot be read on a jobsite
/// with no signal — so the copy in the app is the copy that counts, and the web link below is a
/// convenience rather than the source.
///
/// Parsing is `LegalDocumentOutline`, in the portable layer, under test against these exact
/// files. What is left here is layout: a summary, a contents list that actually goes somewhere,
/// and one card per clause.
struct LegalDocumentView: View {

    let document: LegalDocument
    @Environment(\.openURL) private var openURL

    /// Read and parsed once, not on every body evaluation. It was a computed property, which
    /// meant opening a twenty-kilobyte file from the bundle and re-parsing it every time SwiftUI
    /// re-evaluated this view — including on every jump to a clause, which is the one interaction
    /// the screen has.
    @State private var outline = LegalDocumentOutline(title: "", preamble: [], clauses: [])

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.section) {
                    if outline.isEmpty {
                        missingDocument
                    } else {
                        header(outline)
                        contents(outline, proxy: proxy)
                        ForEach(outline.clauses) { clause in
                            clauseCard(clause).id(clause.id)
                        }
                        footer
                    }
                }
                .padding(.horizontal, Space.comfortable)
                .padding(.top, Space.base)
                .padding(.bottom, Space.screenBottom)
            }
        }
        .offRentScreen()
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("legal.\(document.rawValue)")
        .task {
            guard outline.isEmpty else { return }
            outline = LegalDocumentOutline(markdown: Self.bundledMarkdown(for: document) ?? "")
        }
    }

    // MARK: - Pieces

    private func header(_ outline: LegalDocumentOutline) -> some View {
        VStack(alignment: .leading, spacing: Space.snug) {
            Text(outline.title.isEmpty ? document.title : outline.title)
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text(document.summary)
                .font(Typography.rowDetail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !outline.preamble.isEmpty {
                RowDivider(inset: 0)
                ForEach(Array(outline.preamble.enumerated()), id: \.offset) { _, line in
                    inline(line)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offRentCard()
    }

    private func contents(
        _ outline: LegalDocumentOutline, proxy: ScrollViewProxy
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CardHeader(title: "Contents")
                .padding(.bottom, Space.tight)
            ForEach(outline.clauses) { clause in
                if clause.id > 0 { RowDivider(inset: 0) }
                Button {
                    withAnimation { proxy.scrollTo(clause.id, anchor: .top) }
                } label: {
                    HStack(spacing: Space.snug) {
                        Text(clause.listLabel)
                            .font(Typography.rowTitle)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: Space.snug)
                        Image(systemName: "arrow.down")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Space.snug)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .offRentCard()
    }

    private func clauseCard(_ clause: LegalDocumentOutline.Clause) -> some View {
        VStack(alignment: .leading, spacing: Space.base) {
            HStack(alignment: .firstTextBaseline, spacing: Space.snug) {
                if let number = clause.number {
                    Text(number)
                        .font(Typography.caption.monospacedDigit())
                        .foregroundStyle(Palette.accent)
                        .frame(minWidth: 18, alignment: .leading)
                }
                Text(clause.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(Array(clause.blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let text):
                    inline(text)
                        .font(.callout)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .bullets(let items):
                    VStack(alignment: .leading, spacing: Space.tight) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: Space.snug) {
                                Text("•")
                                    .font(.callout)
                                    .foregroundStyle(Palette.accent)
                                    .accessibilityHidden(true)
                                inline(item)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offRentCard()
    }

    private var footer: some View {
        VStack(spacing: Space.base) {
            if let url = document.plannedURL {
                Button {
                    openURL(url)
                } label: {
                    Label("Read this on the web", systemImage: "safari")
                }
                .buttonStyle(.offRentSecondary)
                .accessibilityIdentifier(A11yID.Settings.legalWebLink)
            }
            if let mail = AppConfiguration.supportMailtoURL {
                Button("Ask a question about this") { openURL(mail) }
                    .font(Typography.rowDetail)
                    .foregroundStyle(.secondary)
                    .minimumTapTarget()
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Not decoration. A screen headed "Privacy Policy" with nothing under it is an App Review
    /// rejection and a broken promise; a short honest message with an address to write to is
    /// neither.
    private var missingDocument: some View {
        VStack(alignment: .leading, spacing: Space.base) {
            Text("This document could not be loaded")
                .font(.headline)
            Text("""
                It ships inside the app, so this should not happen. Write to \
                \(AppConfiguration.supportEmail) and we will send you a copy.
                """)
                .font(Typography.rowDetail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offRentCard()
    }

    // MARK: - Text

    /// Renders `**bold**` and `*emphasis*` without turning line breaks into paragraph breaks.
    private func inline(_ markdown: String) -> Text {
        guard let attributed = try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) else {
            return Text(markdown)
        }
        return Text(attributed)
    }

    static func bundledMarkdown(for document: LegalDocument) -> String? {
        guard let url = Bundle.main.url(forResource: document.resourceName, withExtension: "md")
        else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

#Preview {
    NavigationStack { LegalDocumentView(document: .terms) }
}
