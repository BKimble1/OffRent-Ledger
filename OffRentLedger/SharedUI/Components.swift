import SwiftUI

/// Draws a derived money figure.
///
/// This view is the reason no screen in the app can show a calculated amount without saying it is
/// an estimate: it is the only thing that renders one, and it cannot be constructed without the
/// qualifier. A designer tightening a layout cannot quietly drop the word, because there is no
/// parameter to drop.
struct EstimateLabel: View {
    let amount: Decimal
    var isComplete: Bool = true
    var unavailableReason: String?
    var size: Size = .large
    /// Trailing when the figure sits in the right-hand column of a row, where a left-aligned
    /// qualifier under a right-aligned amount reads as a mistake.
    var alignment: HorizontalAlignment = .leading

    /// `small` is the list-row size: whole dollars, and the qualifier without letter spacing.
    ///
    /// Both are width decisions, measured. At 393pt the trailing column of a rental row is set by
    /// whichever is wider, the figure or the word under it; two decimal places and 0.6pt of
    /// tracking cost about 32pt between them, which is the difference between "EX-0912 · Marlin
    /// Plant Hire" fitting on the row and being truncated mid-vendor. Cents are still shown
    /// wherever the figure is the point of the screen: detail, invoice review, and the summary
    /// panel. The widget already glances at whole dollars, so the two now agree.
    enum Size { case large, medium, small }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            if isComplete {
                Text(size == .small ? Formatters.currencyRounded(amount) : Formatters.currency(amount))
                    .font(font)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                // Sentence case, no letter spacing. Uppercase with tracking was also the widest
                // thing in a row's trailing column — wider than the figure it qualifies.
                Text(AppCopy.estimateQualifier)
                    .font(qualifierFont)
                    .foregroundStyle(.secondary)
            } else {
                Text("Not available")
                    .font(font)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                if let unavailableReason {
                    Text(unavailableReason)
                        .font(qualifierFont)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard isComplete else {
            return "Estimate not available. " + (unavailableReason ?? "")
        }
        return "Estimated \(Formatters.currencyAccessible(amount))"
    }

    private var font: Font {
        switch size {
        case .large: .title
        case .medium: .title3
        case .small: .subheadline
        }
    }

    private var qualifierFont: Font {
        size == .large ? .caption : .caption2
    }
}

/// Status: a small coloured dot and the word.
///
/// Never colour alone — the word carries the meaning and the dot only reinforces it, so a phone
/// in bright sun or a red-green deficiency loses nothing. It used to be a bordered, tinted pill
/// with a symbol in it; a list of those is a list of badges rather than a list of machines.
struct StatusChip: View {
    let status: RentalItemStatus
    var compact = false

    var body: some View {
        HStack(spacing: Space.tight + 1) {
            Image(systemName: status.symbolName)
                .font(compact ? Typography.caption : Typography.rowDetail)
                .imageScale(.small)
            Text(compact ? status.shortName : status.displayName)
                .font(compact ? Typography.caption : Typography.rowDetail)
        }
        .foregroundStyle(Palette.tint(for: status))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(status.displayName)")
        .accessibilityHint(status.explanation)
    }
}

/// The notice that the app does not contact vendors.
///
/// Required wherever the workflow could be read as the app doing the contacting. It is a plain,
/// legible banner rather than a dismissible toast: a disclosure the user can make disappear is a
/// disclosure that was not made.
struct OffRentDisclosureBanner: View {
    var style: Style = .prominent
    var identifier: String?

    enum Style { case prominent, inline }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.bubble.fill")
                .foregroundStyle(Palette.attentionText)
                .font(style == .prominent ? .body : .footnote)
                .accessibilityHidden(true)
            Text(AppCopy.offRentDisclosure)
                .font(style == .prominent ? .subheadline : .footnote)
                .foregroundStyle(style == .prominent ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(style == .prominent ? 14 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if style == .prominent {
                RoundedRectangle(cornerRadius: Radius.card)
                    .fill(Palette.attention.opacity(0.10))
            }
        }
        .overlay {
            if style == .prominent {
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(Palette.attention.opacity(0.30), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Important. \(AppCopy.offRentDisclosure)")
        .accessibilityIdentifier(identifier ?? "disclosure.offRent")
    }
}

/// An empty state that says what to do next, not just that there is nothing here.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var identifier: String?

    var body: some View {
        VStack(spacing: Space.base) {
            // A plain glyph. The tinted disc it used to sit in was the heaviest thing on an
            // otherwise empty screen, which is the wrong emphasis for "there is nothing here".
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .font(Typography.rowDetail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.offRentPrimary)
                    .frame(maxWidth: 240)
                    .padding(.top, Space.snug)
            }
        }
        .padding(.vertical, Space.section)
        .padding(.horizontal, Space.roomy)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier(identifier ?? "emptyState")
    }
}

/// A label/value row that reflows instead of truncating at large Dynamic Type sizes.
struct DetailRow: View {
    let label: String
    let value: String
    var valueIsMonospaced = false
    var identifier: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) { labelView; valueView }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    labelView
                    Spacer(minLength: 12)
                    valueView.multilineTextAlignment(.trailing)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
        .accessibilityIdentifier(identifier ?? "detailRow.\(label)")
    }

    private var labelView: some View {
        Text(label).font(Typography.rowDetail).foregroundStyle(.secondary)
    }

    private var valueView: some View {
        Text(value)
            .font(Typography.rowDetail.weight(.medium))
            .monospacedDigit()
            .fontDesign(valueIsMonospaced ? .monospaced : .default)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Section header above a hand-built group, drawn the way a grouped `List` draws one.
///
/// Today is the only screen that still builds its own groups — it has a hero panel and metric
/// tiles above them — so this exists to keep its headings identical to the real `Section` headers
/// on every other screen. It used to be `.headline` in primary, which made Today's headings a
/// weight heavier than the same headings in Rentals.
struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var count: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: Space.tight + 1) {
                Text(title)
                if let count, count > 0 {
                    Text("\(count)")
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            .font(Typography.sectionTitle)
            .foregroundStyle(.secondary)
            if let subtitle {
                Text(subtitle)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A decimal currency field that never routes user input through `Double`.
struct CurrencyField: View {
    let title: String
    @Binding var value: Decimal?
    var identifier: String?
    var isRequired: Bool = false

    @State private var text: String = ""
    @FocusState private var isFocused: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: Space.base) {
            FieldLabel(title, isRequired: isRequired)
            Spacer(minLength: Space.snug)

            // A box with a currency symbol in it, rather than a bare row with a dash at the end.
            //
            // The old field was a label, a lot of empty space, and an em dash. Nothing said it was
            // money, nothing said it was editable, and the only way to find out was to tap a line
            // that looked like a heading. On a form with three of them in a row, people tapped the
            // wrong one or did not tap at all. The symbol, the border and the zero placeholder are
            // all doing the same job: making a text field look like a text field for money.
            HStack(spacing: 2) {
                Text(verbatim: "$")
                    .font(.body.weight(.medium))
                    .foregroundStyle(text.isEmpty ? .tertiary : .secondary)
                    .accessibilityHidden(true)
                TextField("0.00", text: $text)
                    .font(.body.weight(.medium))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .focused($isFocused)
                    .accessibilityIdentifier(identifier ?? "currencyField.\(title)")
                    .accessibilityLabel(isRequired ? "\(title), required, in dollars" : "\(title), in dollars")
                .onChange(of: text) { _, newValue in
                    value = newValue.isEmpty ? nil : MoneyMath.parse(newValue)
                }
                .onChange(of: isFocused) { _, focused in
                    // Reformat only on blur. Reformatting while typing moves the caret and makes
                    // "285." impossible to type.
                    guard !focused, let value else { return }
                    text = "\(MoneyMath.rounded(value))"
                }
                // The decimal pad has no return key. Without this there is no way to put it away
                // except by tapping some other control, which on a long form means scrolling
                // blind behind a keyboard covering half the screen.
                    .toolbar {
                        if isFocused {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") { isFocused = false }
                            }
                        }
                    }
            }
            .padding(.horizontal, Space.snug)
            .padding(.vertical, Space.tight)
            .frame(minWidth: 96)
            .background(Palette.sunken, in: RoundedRectangle(cornerRadius: Radius.control))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control)
                    .strokeBorder(
                        isFocused ? Palette.accent : Palette.edge(contrast),
                        lineWidth: isFocused ? 2 : Layout.edgeWidth(contrast)
                    )
            )
            // The whole box takes the tap, not just the glyphs inside it.
            .contentShape(Rectangle())
            .onTapGesture { isFocused = true }
        }
        .minimumTapTarget()
        .onAppear { if let value { text = "\(MoneyMath.rounded(value))" } }
    }
}

/// A field's name, with the mark that says it cannot be left empty.
///
/// One component so "required" looks the same everywhere and is spoken the same way. VoiceOver
/// gets the word; sighted users get the asterisk, in the attention colour rather than plain red,
/// which is the palette's own and clears 4.5:1 on every surface it sits on.
struct FieldLabel: View {
    let title: String
    var isRequired: Bool = false

    init(_ title: String, isRequired: Bool = false) {
        self.title = title
        self.isRequired = isRequired
    }

    var body: some View {
        HStack(spacing: 2) {
            Text(title)
            if isRequired {
                Text(verbatim: "*")
                    .foregroundStyle(Palette.attentionText)
                    .accessibilityHidden(true)
            }
        }
        .font(Typography.rowDetail)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isRequired ? "\(title), required" : title)
    }
}

/// The line that explains the asterisk. One per form, under the first section that uses one.
struct RequiredLegend: View {
    var body: some View {
        (Text(verbatim: "* ").foregroundColor(Palette.attentionText) + Text("Required to save."))
            .font(Typography.micro)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Fields marked with an asterisk are required to save.")
    }
}

// MARK: - Structure
//
// The components below exist because the app was drawing the same shapes by hand on every
// screen, each time slightly differently, and each time inside its own rounded box. A list of
// five things became five floating rectangles on a background the same colour as they were.

/// The one dominant panel on a screen: graphite, carrying the fact the screen is about.
///
/// Exactly one per screen. Two competing dark panels is the same problem as none.
struct SummaryPanel<Trailing: View>: View {
    let eyebrow: String
    let headline: AnyView
    /// A full-width line under the headline row — what this panel is *about*, as opposed to the
    /// figure itself. It has its own line because sharing the headline row with the trailing pill
    /// wrapped "Cedar Ridge Equipment · Bayview Tower" onto three lines with the pill on top of it.
    var subhead: String?
    var footnote: String?
    @ViewBuilder var trailing: Trailing

    init(eyebrow: String, subhead: String? = nil, footnote: String? = nil,
         @ViewBuilder headline: () -> some View,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.eyebrow = eyebrow
        self.subhead = subhead
        self.footnote = footnote
        self.headline = AnyView(headline())
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.base) {
            // The eyebrow gets the full width. Sharing the line with the trailing pill wrapped
            // "Estimated rent running" onto two lines at default type, which is the one string
            // on this screen the product specification fixes word for word.
            Text(eyebrow)
                .font(Typography.caption.weight(.semibold))
                .foregroundStyle(Palette.onGraphiteSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .bottom) {
                headline
                Spacer(minLength: Space.snug)
                trailing
            }
            if let subhead {
                Text(subhead)
                    .font(Typography.rowDetail)
                    .foregroundStyle(Palette.onGraphite)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let footnote {
                Text(footnote)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.onGraphiteSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .offRentPanel()
        .accessibilityElement(children: .contain)
    }
}

/// A small figure with a label. Three across the width of a phone; never more.
///
/// Compact: the value, the label, and nothing else. The tinted symbol above each one made a row
/// of three tiles into a row of three logos.
///
/// It used to hold both lines to one line each and shrink them to fit — 0.7 on the figure, 0.85
/// on the label. At the largest accessibility sizes that is a tile a third of a phone wide
/// showing "To collec…" over a number set smaller than the caption under it, which is the
/// opposite of what somebody who has turned those sizes on asked for. Both lines wrap now and
/// the tile grows to hold them.
struct MetricTile: View {
    let value: String
    let label: String
    var symbol: String?
    var tint: Color = .primary
    var identifier: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.hair) {
            Text(value)
                .font(Typography.metric)
                .monospacedDigit()
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        // `maxHeight: .infinity` is what keeps a row of these level once one of them wraps onto
        // a second line: an `HStack` proposes its own height to every child, so each tile fills
        // the tallest rather than floating at its own size. The padding in `offRentCard` is
        // applied outside this frame, so the card is exactly the row's height, not more.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .offRentCard(padding: Space.base)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
        .accessibilityIdentifier(identifier ?? "metric.\(label)")
    }
}

/// A small leading glyph on a row.
///
/// Plain, and secondary by default. This used to draw a tinted rounded square behind every
/// symbol; a screen of those is a screen of orange chips, and the brief is that orange belongs to
/// the primary action and small highlights only.
struct RowIcon: View {
    let symbol: String
    var tint: Color = .secondary

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: Layout.symbolInline + 2, weight: .regular))
            .foregroundStyle(tint)
            .frame(width: Layout.rowIcon, alignment: .leading)
            .accessibilityHidden(true)
    }
}

/// Rows sharing one surface, divided by hairlines.
///
/// This replaces the pattern of giving every row its own card. On a page the same colour as the
/// cards, a stack of separate boxes reads as nothing at all; one grouped surface reads as a list.
struct ListGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .offRentGroup()
    }
}

/// A divider that lines up with row content rather than running the full width.
struct RowDivider: View {
    var inset: CGFloat = Space.comfortable + Layout.rowIcon + Space.base

    var body: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: Layout.hairline)
            .padding(.leading, inset)
            .accessibilityHidden(true)
    }
}

/// One rental, understandable at a glance: what it is, whose it is, where it stands, what it is
/// costing, and what to do about it.
struct RentalRow: View {
    let title: String
    var reference: String?
    var vendor: String?
    let status: RentalItemStatus
    var amount: Decimal?
    var amountIsComplete: Bool = true
    /// Off inside a section that is already grouped by status — repeating "Contact vendor" on
    /// every row of the Contact vendor section costs a third of the row's width and says nothing.
    /// On the Rentals list, where statuses are mixed, it earns its place.
    var showsStatus: Bool = true
    var note: String?
    var noteTint: Color?
    var identifier: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize { stacked } else { standard }
        }
        .padding(.horizontal, Space.comfortable)
        .padding(.vertical, Space.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier ?? "rentalRow")
    }

    /// Two columns: what it is on the left, what it is costing on the right.
    ///
    /// No leading icon. A tinted glyph on every row of a list is decoration that repeats the
    /// status word two lines below it, and it costs 40pt of the width the equipment name needs.
    private var standard: some View {
        HStack(alignment: .top, spacing: Space.base) {
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(title)
                    .font(Typography.rowTitle)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.rowDetail)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                statusLine
            }
            Spacer(minLength: Space.snug)
            amountView
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if showsStatus || note != nil {
            HStack(spacing: Space.tight + 1) {
                if showsStatus {
                    Circle()
                        .fill(Palette.tint(for: status))
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(status.shortName)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.tint(for: status))
                        .accessibilityLabel(status.displayName)
                }
                if let note {
                    if showsStatus {
                        Text("·").font(Typography.caption).foregroundStyle(.tertiary)
                    }
                    Text(note)
                        .font(Typography.caption)
                        .foregroundStyle(noteTint ?? .secondary)
                }
            }
            .lineLimit(1)
            .padding(.top, 1)
        }
    }

    /// One column. At accessibility type sizes the three-column arrangement leaves the equipment
    /// name about forty points, so there is nothing to preserve by keeping it.
    private var stacked: some View {
        VStack(alignment: .leading, spacing: Space.snug) {
            Text(title).font(Typography.rowTitle).fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(Typography.rowDetail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsStatus { StatusChip(status: status, compact: true) }
            amountView
            if let note {
                Text(note)
                    .font(Typography.caption)
                    .foregroundStyle(noteTint ?? .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // Through `EstimateLabel`, never as a bare `Formatters.currency`. A derived figure in this app
    // is always drawn with its qualifier, and the only way to keep that true is for rows to have
    // no way of rendering one without it.
    @ViewBuilder
    private var amountView: some View {
        if let amount, amountIsComplete {
            EstimateLabel(
                amount: amount, size: .small,
                alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing
            )
        }
    }

    private var subtitle: String? {
        let parts = [reference, vendor].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A short message that belongs to the content, not to a modal.
struct InlineAlert: View {
    enum Kind { case attention, info, positive }

    let message: String
    var kind: Kind = .attention
    var symbol: String?

    private var tint: Color {
        switch kind {
        case .attention: Palette.attention
        case .info: .secondary
        case .positive: Palette.settled
        }
    }

    private var defaultSymbol: String {
        switch kind {
        case .attention: "exclamationmark.circle"
        case .info: "info.circle"
        case .positive: "checkmark.circle"
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.snug) {
            Image(systemName: symbol ?? defaultSymbol)
                .font(Typography.rowDetail)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(message)
                .font(Typography.rowDetail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Expected against invoiced, and the gap between them.
///
/// The whole point of the screen it sits on, so it is one component rather than three rows of
/// label/value that a reader has to subtract in their head. A difference is drawn as a
/// *possible* one: emphasis, not alarm, and never the word "wrong".
struct VariancePanel: View {
    let expected: Decimal?
    let invoiced: Decimal
    let variance: Decimal
    var isMatch: Bool
    var identifier: String?

    private var tint: Color { isMatch ? Palette.settled : Palette.review }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.base) {
            amountRow("Expected", expected.map(Formatters.currency) ?? "Not available")
            RowDivider(inset: 0)
            amountRow("Invoiced", Formatters.currency(invoiced))
            RowDivider(inset: 0)
            HStack(alignment: .firstTextBaseline) {
                Label {
                    Text(isMatch ? "No difference" : "Possible difference")
                        .font(Typography.rowTitle)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: isMatch ? "checkmark.seal.fill" : "questionmark.circle.fill")
                        .font(Typography.rowDetail)
                }
                .foregroundStyle(tint)
                Spacer(minLength: Space.snug)
                VStack(alignment: .trailing, spacing: 2) {
                    // Deliberately left as an ordinary `Text` with no accessibility label of its
                    // own: the figure's label is the figure, which is what the UI test asserts is
                    // on screen and what VoiceOver should read after "Possible difference".
                    Text(Formatters.currency(variance))
                        .font(Typography.metric)
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .accessibilityIdentifier(identifier ?? "variancePanel.amount")
                    Text(AppCopy.estimateQualifier)
                        .font(Typography.micro)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(Space.comfortable)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(Palette.hairline, lineWidth: Layout.hairline)
        )
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    private func amountRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(Typography.rowDetail)
                .foregroundStyle(.secondary)
            Spacer(minLength: Space.snug)
            Text(value)
                .font(Typography.rowTitle)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

/// The action area pinned to the bottom of a screen, over a surface so content scrolls under it
/// legibly rather than through it.
struct StickyActionBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: Layout.hairline)
            content
                .padding(.horizontal, Space.comfortable)
                .padding(.top, Space.base)
                .padding(.bottom, Space.snug)
        }
        // Full width, always.
        //
        // A `VStack` sizes to its content, so a bar whose content did not itself stretch drew a
        // short strip floating in the middle of the screen with the page showing either side of
        // it. It is a bar; it spans the bar's width.
        .frame(maxWidth: .infinity)
        .background(Palette.raised)
    }
}

/// A selectable filter, drawn as a small pill with its count.
///
/// This is the status filter made visible. It used to live inside a menu behind a toolbar icon,
/// which meant the answer to "how many of these need a phone call?" was three taps away and the
/// current filter was invisible once the menu closed.
struct FilterChip: View {
    let title: String
    var count: Int?
    var isSelected: Bool
    var tint: Color = Palette.accent
    let action: () -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.tight + 1) {
                Text(title)
                if let count {
                    Text("\(count)")
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? Palette.onAccent.opacity(0.65) : .secondary)
                }
            }
            .font(Typography.rowDetail.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? Palette.onAccent : Color.primary)
            .padding(.horizontal, Space.base - 1)
            .padding(.vertical, Space.tight + 2)
            .background(isSelected ? tint : Palette.raised, in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? Palette.fillEdge(contrast) : Palette.edge(contrast),
                    lineWidth: Layout.edgeWidth(contrast)
                )
            )
            // The pill stays the size it draws — about 32pt tall, which is what a row of these
            // is meant to look like — and the *target* around it is 44pt in both directions.
            // Apple's minimum is not a visual instruction, and a chip inflated to 44pt of fill
            // is a chip that has stopped being a chip. Gloves and a moving truck are the reason
            // this matters here rather than a rule being followed for its own sake.
            .frame(minWidth: Layout.minimumTapTarget, minHeight: Layout.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(traits)
    }

    private var traits: AccessibilityTraits {
        var traits: AccessibilityTraits = .isButton
        if isSelected { traits.insert(.isSelected) }
        return traits
    }
}

/// A row that navigates somewhere, inside a `ListGroup`.
struct NavigationRow: View {
    let title: String
    var subtitle: String?
    let symbol: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: Space.base) {
            RowIcon(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Typography.rowTitle)
                if let subtitle {
                    Text(subtitle).font(Typography.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Space.snug)
            Image(systemName: "chevron.right")
                .font(Typography.micro.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Space.comfortable)
        .padding(.vertical, Space.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// A button drawn as a row inside a `ListGroup`.
///
/// The counterpart to `NavigationRow` for things that happen here rather than push a screen.
/// Both exist so a group of actions reads as one list rather than as a column of loose buttons,
/// which is what they looked like once the screens left `Form`.
struct ActionRow: View {
    let title: String
    var subtitle: String?
    let symbol: String
    var tint: Color = .secondary
    /// Draws the "leaves the app" glyph — used where tapping hands off to Phone, Mail or Safari.
    var opensExternally = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.base) {
                RowIcon(symbol: symbol, tint: tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Typography.rowTitle)
                        .foregroundStyle(isEnabled ? Color.primary : Palette.disabledLabel)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Space.snug)
                if opensExternally {
                    Image(systemName: "arrow.up.forward")
                        .font(Typography.micro.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Space.comfortable)
            .padding(.vertical, Space.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .minimumTapTarget()
    }
}

/// The heading of a card: a small tinted symbol, a title, and optional supporting line.
struct CardHeader: View {
    let title: String
    var subtitle: String?
    var symbol: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.snug) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: Layout.symbolInline, weight: .semibold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.rowDetail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
