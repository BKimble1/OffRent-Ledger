import SwiftUI

/// The visual identity, in one place.
///
/// Field-ready, calm, native. Warm construction orange for action and attention; graphite and
/// warm stone for structure. Every screen draws from these tokens rather than reaching for a
/// system colour or a hand-typed number, which is what keeps eleven screens looking like one app.
///
/// Deliberately absent: gradients on surfaces, glass, decorative charts, invented machinery, and
/// any colour that carries meaning on its own. Every status is label + symbol + colour, so
/// removing the colour loses nothing.
enum Palette {

    // MARK: - Brand

    /// Construction orange. The accent, primary actions, and "attention". Never a background
    /// behind body text on a light surface — it fails contrast there, and `OnAccent` exists for
    /// the one case where it *is* the background.
    static let accent = Color("AccentColor")

    /// Attention, not alarm. An item needing a phone call is not an error.
    static let attention = Color("AttentionColor")
    /// Something the user should look at on an invoice.
    static let review = Color("ReviewColor")
    /// Done.
    static let settled = Color("SettledColor")
    /// Off-rent, awaiting something outside the user's control.
    static let waiting = Color("WaitingColor")

    // MARK: - Surfaces
    //
    // Four planes, and the order matters more than the hue. See `scripts/generate_assets.py`:
    // the first attempt at this was warm but measured 1.11:1 between ground and card, which is
    // invisible — the reason the app read as blank pages with text on them. These are 1.24:1.

    /// The page. Soft stone in light, near-black in dark.
    static let background = Color("SurfaceBackground")
    /// Cards and rows that sit on the page. Warm ivory in light.
    static let raised = Color("SurfaceRaised")
    /// Wells: inputs, inset groups, anything that should read as cut into the page.
    static let sunken = Color("SurfaceSunken")
    /// The one dominant panel per screen. Deep graphite; carries `onGraphite` text.
    static let graphite = Color("SurfaceGraphite")

    /// Text and symbols on `graphite`. Fixed, not adaptive: the panel is dark in both schemes.
    static let onGraphite = Color(red: 0.965, green: 0.945, blue: 0.910)
    /// Secondary text on `graphite`. 7.9:1 — still comfortably readable outdoors.
    static let onGraphiteSecondary = Color(red: 0.729, green: 0.702, blue: 0.655)
    /// Text on an orange fill. Graphite, at 7.4:1 — white would be 2.4:1 and fail.
    static let onAccent = Color(red: 0.090, green: 0.102, blue: 0.122)

    /// Hairlines and dividers.
    static let hairline = Color("HairlineColor")

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

/// Type. Six roles, so a screen cannot end up with five near-identical sizes — which is what
/// happened when Today drew three consecutive rows at `.subheadline`, `.caption`, `.caption`.
enum Typography {
    /// The one number a screen is about.
    static let hero = Font.system(.largeTitle, design: .rounded).weight(.semibold)
    /// A metric inside a tile.
    static let metric = Font.system(.title2, design: .rounded).weight(.semibold)
    /// Section headings.
    static let sectionTitle = Font.headline
    /// The primary line of a row — the equipment name.
    static let rowTitle = Font.subheadline.weight(.semibold)
    /// The supporting line of a row.
    static let rowDetail = Font.footnote
    /// Labels, qualifiers, counts.
    static let caption = Font.caption
    /// The smallest thing the app draws. Nothing below this.
    static let micro = Font.caption2
}

/// Spacing on a 4pt grid. Named by intent so a screen asks for "the gap between sections"
/// rather than for "20".
enum Space {
    static let hair: CGFloat = 2
    static let tight: CGFloat = 4
    static let snug: CGFloat = 8
    static let base: CGFloat = 12
    static let comfortable: CGFloat = 16
    static let roomy: CGFloat = 24
    static let section: CGFloat = 28
    static let screenTop: CGFloat = 8
    static let screenBottom: CGFloat = 40
}

enum Radius {
    static let control: CGFloat = 10
    static let card: CGFloat = 14
    static let panel: CGFloat = 20
}

enum Layout {
    /// Apple's minimum comfortable target. Everything tappable clears it.
    static let minimumTapTarget: CGFloat = 44
    static let controlHeight: CGFloat = 50
    static let rowIcon: CGFloat = 34
    static let symbolInline: CGFloat = 15
    static let hairline: CGFloat = 1

    // Kept so existing call sites do not all have to change at once.
    static let cardCornerRadius = Radius.card
    static let cardPadding = Space.comfortable
    static let sectionSpacing = Space.section
    static let itemSpacing = Space.snug
}

/// Motion. Short, native, and never in the way of somebody entering a rate in a truck.
enum Motion {
    static let quick = Animation.easeOut(duration: 0.18)
    static let standard = Animation.easeInOut(duration: 0.24)
    static let spring = Animation.spring(response: 0.34, dampingFraction: 0.86)
}

// MARK: - Surface modifiers

extension View {

    /// A raised surface. One hairline, no shadow stack, no gradient — a list of these stays
    /// legible in bright sun on a jobsite, which a pile of translucency does not.
    func offRentCard(padding: CGFloat = Space.comfortable,
                     radius: CGFloat = Radius.card) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Palette.hairline, lineWidth: Layout.hairline)
            )
    }

    /// The dominant panel. One per screen, at the top, carrying the fact the screen is about.
    func offRentPanel(padding: CGFloat = Space.roomy) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.graphite, in: RoundedRectangle(cornerRadius: Radius.panel))
    }

    /// A group of rows sharing one surface, with hairlines between them — rather than each row
    /// in its own box, which is how a list of five things becomes five floating rectangles.
    func offRentGroup() -> some View {
        self
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(Palette.hairline, lineWidth: Layout.hairline)
            )
    }

    /// The page. Every screen sets this; nothing uses `.systemGroupedBackground` any more.
    func offRentScreen() -> some View {
        background(Palette.background.ignoresSafeArea())
    }

    /// The page, for a `Form` or a `List`.
    ///
    /// Fifteen screens were drawing iOS's own grouped background — a cool #F2F2F7 behind white
    /// rows, four luminance levels apart — which is most of why the app read as blank pages with
    /// text on them. Hiding the scroll background and painting the warm ground underneath puts
    /// the rows on a surface they can actually be seen against.
    func offRentFormBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Palette.background.ignoresSafeArea())
            // Warm ivory rows rather than pure white. Applied to the container so a form does
            // not have to repeat it on forty rows; a row that wants something else still wins,
            // because the nearer modifier does.
            .listRowBackground(Palette.raised)
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

// MARK: - Button styles

/// The primary action. Orange fill, graphite label — the one combination in the palette that is
/// both the brand colour and readable at 7.4:1.
struct OffRentPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(isEnabled ? Palette.onAccent : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: Layout.controlHeight)
            .background(
                isEnabled ? Palette.accent : Palette.sunken,
                in: RoundedRectangle(cornerRadius: Radius.control)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

/// The secondary action. An outline, so a screen never has two orange buttons competing.
struct OffRentSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: Layout.controlHeight)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.control))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control)
                    .strokeBorder(Palette.hairline, lineWidth: Layout.hairline)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == OffRentPrimaryButtonStyle {
    static var offRentPrimary: OffRentPrimaryButtonStyle { OffRentPrimaryButtonStyle() }
}

extension ButtonStyle where Self == OffRentSecondaryButtonStyle {
    static var offRentSecondary: OffRentSecondaryButtonStyle { OffRentSecondaryButtonStyle() }
}
