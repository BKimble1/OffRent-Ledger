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

/// Status, drawn as symbol + text + colour.
///
/// Never colour alone. Somebody with a red-green deficiency, or a phone in bright sun, still
/// reads "Contact Vendor" — the tint is reinforcement, not the message.
struct StatusChip: View {
    let status: RentalItemStatus
    var compact = false

    var body: some View {
        Label {
            // Compact uses the short name; the accessibility label below always speaks the full
            // one, so the abbreviation is never the only form of the word available.
            Text(compact ? status.shortName : status.displayName)
                .font(compact ? .caption2 : .caption)
                .fontWeight(.medium)
        } icon: {
            Image(systemName: status.symbolName)
                .font(compact ? .caption2 : .caption)
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, compact ? Space.snug : Space.base - 2)
        .padding(.vertical, compact ? 3 : 5)
        .background(Palette.tint(for: status).opacity(0.14), in: Capsule())
        .foregroundStyle(Palette.tint(for: status))
        .overlay(Capsule().strokeBorder(Palette.tint(for: status).opacity(0.34), lineWidth: 1))
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
                .foregroundStyle(Palette.attention)
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
            // A quiet disc rather than a large loose glyph. It gives the state a centre of
            // gravity at a fraction of the visual weight of an illustration.
            ZStack {
                Circle()
                    .fill(Palette.sunken)
                    .frame(width: 68, height: 68)
                Image(systemName: symbol)
                    .font(.system(size: 27, weight: .regular))
                    .foregroundStyle(Palette.accent)
            }
            .accessibilityHidden(true)
            .padding(.bottom, Space.tight)

            Text(title)
                .font(Typography.sectionTitle)
                .multilineTextAlignment(.center)
            Text(message)
                .font(Typography.rowDetail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.offRentPrimary)
                    .frame(maxWidth: 260)
                    .padding(.top, Space.tight)
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

/// Section header used above card groups on Today and in detail screens.
struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var count: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).font(Typography.sectionTitle)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(Typography.micro.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Space.snug - 1)
                        .padding(.vertical, 2)
                        .background(Palette.sunken, in: Capsule())
                }
            }
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
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

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Text(title).font(Typography.rowDetail).foregroundStyle(.secondary)
            Spacer(minLength: Space.base)
            TextField("—", text: $text)
                .font(.body.weight(.medium))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .focused($isFocused)
                .accessibilityIdentifier(identifier ?? "currencyField.\(title)")
                .onChange(of: text) { _, newValue in
                    value = newValue.isEmpty ? nil : MoneyMath.parse(newValue)
                }
                .onChange(of: isFocused) { _, focused in
                    // Reformat only on blur. Reformatting while typing moves the caret and makes
                    // "285." impossible to type.
                    guard !focused, let value else { return }
                    text = "\(MoneyMath.rounded(value))"
                }
        }
        .minimumTapTarget()
        .onAppear { if let value { text = "\(MoneyMath.rounded(value))" } }
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
struct MetricTile: View {
    let value: String
    let label: String
    var symbol: String?
    var tint: Color = .primary
    var identifier: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.tight) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: Layout.symbolInline, weight: .semibold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
            Text(value)
                .font(Typography.metric)
                .monospacedDigit()
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(Typography.micro)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .offRentCard(padding: Space.base)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
        .accessibilityIdentifier(identifier ?? "metric.\(label)")
    }
}

/// The leading anchor on a row: a symbol in a tinted disc.
///
/// Small, quiet, and the reason a list of rentals scans as a list of *machines* rather than as
/// paragraphs of text.
struct RowIcon: View {
    let symbol: String
    var tint: Color = Palette.accent

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.control - 1)
                .fill(tint.opacity(0.13))
            Image(systemName: symbol)
                .font(.system(size: Layout.symbolInline, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: Layout.rowIcon, height: Layout.rowIcon)
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
    /// Status is the tinted symbol plus the first word of the third line, not a pill. Measured at
    /// 393pt: a pill in the trailing column made that column about 130pt wide and left the
    /// equipment name 190pt, which wrapped "Skid Steer Loader 75HP" and truncated the vendor. The
    /// pill still appears at accessibility sizes and on the detail screen, where there is room.
    private var standard: some View {
        HStack(alignment: .top, spacing: Space.base) {
            RowIcon(symbol: status.symbolName, tint: Palette.tint(for: status))
            VStack(alignment: .leading, spacing: Space.tight) {
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
            Image(systemName: "chevron.right")
                .font(Typography.micro.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 3)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if showsStatus || note != nil {
            HStack(spacing: Space.tight) {
                if showsStatus {
                    Text(status.shortName)
                        .font(Typography.caption.weight(.semibold))
                        .foregroundStyle(Palette.tint(for: status))
                        .accessibilityLabel(status.displayName)
                    if note != nil {
                        Text("·").font(Typography.caption).foregroundStyle(.tertiary)
                    }
                }
                if let note {
                    Text(note)
                        .font(Typography.caption)
                        .foregroundStyle(noteTint ?? .secondary)
                }
            }
            .lineLimit(1)
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
        case .attention: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        case .positive: "checkmark.circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Space.snug + 2) {
            Image(systemName: symbol ?? defaultSymbol)
                .font(Typography.rowDetail)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(message)
                .font(Typography.rowDetail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: Radius.control))
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
                .strokeBorder(tint.opacity(0.42), lineWidth: 1.5)
        )
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
        .background(Palette.raised)
    }
}

/// A selectable filter, drawn as a pill with its count.
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

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.tight + 2) {
                Text(title)
                    .font(Typography.rowDetail.weight(isSelected ? .semibold : .regular))
                if let count {
                    Text("\(count)")
                        .font(Typography.micro.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? Palette.onAccent.opacity(0.7) : .secondary)
                }
            }
            .foregroundStyle(isSelected ? Palette.onAccent : Color.primary)
            .padding(.horizontal, Space.base)
            .padding(.vertical, Space.snug)
            .background(isSelected ? tint : Palette.raised, in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? Color.clear : Palette.hairline, lineWidth: Layout.hairline
                )
            )
        }
        .buttonStyle(.plain)
        .minimumTapTarget()
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
    var tint: Color = Palette.accent

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
    var tint: Color = Palette.accent
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
                        .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
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
    var tint: Color = Palette.accent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.snug) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: Layout.symbolInline, weight: .semibold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typography.sectionTitle)
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
