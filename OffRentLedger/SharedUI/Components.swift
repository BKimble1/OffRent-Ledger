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

    enum Size { case large, medium, small }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if isComplete {
                Text(Formatters.currency(amount))
                    .font(font)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(AppCopy.estimateQualifier)
                    .font(qualifierFont)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
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
        case .large: .system(.title, design: .rounded)
        case .medium: .system(.title3, design: .rounded)
        case .small: .system(.body, design: .rounded)
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
            Text(status.displayName)
                .font(compact ? .caption2 : .caption)
                .fontWeight(.medium)
        } icon: {
            Image(systemName: status.symbolName)
                .font(compact ? .caption2 : .caption)
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 3 : 4)
        .background(Palette.tint(for: status).opacity(0.15), in: Capsule())
        .foregroundStyle(Palette.tint(for: status))
        .overlay(Capsule().strokeBorder(Palette.tint(for: status).opacity(0.3), lineWidth: 0.5))
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
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .fill(Palette.attention.opacity(0.10))
            }
        }
        .overlay {
            if style == .prominent {
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .strokeBorder(Palette.attention.opacity(0.28), lineWidth: 1)
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
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .minimumTapTarget()
            }
        }
        .padding(28)
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
        Text(label).font(.subheadline).foregroundStyle(.secondary)
    }

    private var valueView: some View {
        Text(value)
            .font(.subheadline)
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
                Text(title).font(.headline)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.caption)
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
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
            Text(title)
            Spacer(minLength: 12)
            TextField("—", text: $text)
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

/// Wraps a Pro-only control. Tapping it opens the paywall rather than doing nothing.
struct ProGate<Content: View>: View {
    let feature: ProFeature
    let entitlement: EntitlementState
    let onBlocked: (PaywallReason) -> Void
    let reason: PaywallReason
    @ViewBuilder let content: () -> Content

    var body: some View {
        if EntitlementPolicy.isAllowed(feature, entitlement: entitlement) {
            content()
        } else {
            Button { onBlocked(reason) } label: {
                HStack {
                    content().disabled(true)
                    Spacer(minLength: 8)
                    Label("Pro", systemImage: "lock.fill")
                        .font(.caption2)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(Palette.accent)
                }
            }
            .buttonStyle(.plain)
            .minimumTapTarget()
            .accessibilityHint("\(feature.displayName) is part of \(AppConfiguration.displayName) Pro. Opens the subscription options.")
        }
    }
}
