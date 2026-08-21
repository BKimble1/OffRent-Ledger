import SwiftUI

/// The visual identity.
///
/// Field-ready, calm, native. A warm construction orange for action and attention, graphite and
/// slate for everything else, and system backgrounds underneath so the app looks like it belongs
/// on the phone rather than like a website in a wrapper.
///
/// Deliberately absent: gradients on surfaces, glass everywhere, decorative charts, invented
/// machinery illustrations, and any colour that carries meaning on its own. Every status is drawn
/// as label + symbol + colour, so removing the colour loses nothing.
enum Palette {

    /// Construction orange. Used for the accent, for primary actions, and for "attention" —
    /// never as a background behind body text.
    static let accent = Color("AccentColor")

    /// Attention, not alarm. An item needing a phone call is not an error.
    static let attention = Color("AttentionColor")
    /// Something the user should look at on an invoice.
    static let review = Color("ReviewColor")
    /// Done.
    static let settled = Color("SettledColor")
    /// Off-rent, awaiting something outside the user's control.
    static let waiting = Color("WaitingColor")

    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let groupedBackground = Color(.systemGroupedBackground)
    static let separator = Color(.separator)

    static func tint(for status: RentalItemStatus) -> Color {
        switch status {
        case .draft: .secondary
        case .active: accent
        case .contactVendor: attention
        case .confirmationRecorded, .awaitingPickup, .pickedUp, .awaitingInvoice: waiting
        case .invoiceReview: review
        case .needsFollowUp: attention
        case .resolved: settled
        case .archived: .secondary
        }
    }
}

enum Layout {
    /// Apple's minimum comfortable target. Everything tappable clears it.
    static let minimumTapTarget: CGFloat = 44
    static let cardCornerRadius: CGFloat = 14
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 20
    static let itemSpacing: CGFloat = 8
}

extension View {
    /// The one card treatment in the app. A single rounded surface with a hairline, no shadow
    /// stack and no gradient — a list of these stays legible in bright sun on a jobsite, which a
    /// pile of translucency does not.
    func offRentCard(padding: CGFloat = Layout.cardPadding) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.cardBackground, in: RoundedRectangle(cornerRadius: Layout.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Layout.cardCornerRadius)
                    .strokeBorder(Palette.separator.opacity(0.5), lineWidth: 0.5)
            )
    }

    /// Guarantees a hit target at least 44pt tall without changing visual size.
    func minimumTapTarget() -> some View {
        frame(minHeight: Layout.minimumTapTarget)
            .contentShape(Rectangle())
    }

    /// Honours Reduce Motion by dropping to a cross-fade rather than removing feedback entirely.
    func respectfulAnimation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(RespectfulAnimation(animation: animation, value: value))
    }
}

private struct RespectfulAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation?
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? .default : animation, value: value)
    }
}
