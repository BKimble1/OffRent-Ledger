import SwiftUI

/// The visual identity, in one place.
///
/// Quiet, warm and native. A warm-white page, white cards separated by a hairline rather than by
/// a change of fill, graphite text, and orange reserved for the primary action and small
/// highlights. One dark panel exists in the whole app, on Today.
///
/// The previous pass went the other way — soft-stone ground behind ivory cards, a graphite panel
/// on most screens — and it read as heavy and over-designed. Separation is drawn at the edges now,
/// which is what the platform does and what keeps a screen full of records legible.
///
/// Deliberately absent: gradients on surfaces, glass, decorative charts, tinted icon discs on
/// every row, and any colour that carries meaning on its own. Every status is label + colour, so
/// removing the colour loses nothing.
enum Palette {

    // MARK: - Brand

    /// Construction orange. Primary actions and small highlights only — never a fill behind body
    /// text on a light surface, where it fails contrast. `onAccent` is for the one case where it
    /// *is* the background.
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
    // Ground to card is 1.09:1 — invisible on its own, and meant to be. The hairline is 1.42:1
    // against the card, and that is what draws the boundary. See `scripts/generate_assets.py`.

    /// The page. Warm white.
    static let background = Color("SurfaceBackground")
    /// Cards and rows. White.
    static let raised = Color("SurfaceRaised")
    /// Wells: search fields, inset groups, anything cut into the page.
    static let sunken = Color("SurfaceSunken")
    /// The one dark panel in the app, on Today. Not a surface anything else paints with.
    static let graphite = Color("SurfaceGraphite")

    /// Text on `graphite`. Fixed, not adaptive: the panel is dark in both schemes.
    static let onGraphite = Color(red: 0.976, green: 0.973, blue: 0.965)
    /// Secondary text on `graphite`, at 8.1:1.
    static let onGraphiteSecondary = Color(red: 0.729, green: 0.718, blue: 0.702)
    /// Text on an orange fill. Graphite, at 7.4:1 — white would be 2.4:1 and fail.
    static let onAccent = Color(red: 0.090, green: 0.102, blue: 0.122)

    /// Hairlines, dividers and card edges.
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
    // The plain system face throughout. An earlier pass set the money figures in SF Rounded,
    // which reads as friendly — wrong for a document somebody may end up putting in front of a
    // rental company. Numbers are `monospacedDigit` where they sit in a column, which is an
    // alignment decision rather than a stylistic one.

    /// The one number a screen is about.
    static let hero = Font.largeTitle.weight(.semibold)
    /// A metric inside a tile.
    static let metric = Font.title2.weight(.semibold)
    /// Section headings. Footnote semibold in secondary — what a grouped `List` draws, so the
    /// one screen that builds its own groups matches the ones that do not.
    static let sectionTitle = Font.footnote.weight(.semibold)
    /// The primary line of a row — the equipment name. Body, as a native list row is: at
    /// subheadline it read as a caption of something rather than as the thing itself.
    static let rowTitle = Font.body
    /// The supporting line of a row.
    static let rowDetail = Font.subheadline
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
    static let roomy: CGFloat = 20
    static let section: CGFloat = 24
    static let screenTop: CGFloat = 8
    static let screenBottom: CGFloat = 40
}

/// Corner radii, matched to the platform. An inset-grouped `List` draws its own group at 10pt,
/// so a hand-built card at 14 sitting above one at 10 was visibly a different shape.
enum Radius {
    static let control: CGFloat = 10
    static let card: CGFloat = 12
    static let panel: CGFloat = 16
}

enum Layout {
    /// Apple's minimum comfortable target. Everything tappable clears it.
    static let minimumTapTarget: CGFloat = 44
    static let controlHeight: CGFloat = 48
    static let rowIcon: CGFloat = 28
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

    /// A card: white, a hairline, and a shadow soft enough that you notice the edge rather than
    /// the shadow. No stacked shadows, no gradient — this has to stay legible in bright sun.
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
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    /// The one dark panel in the app. Today only.
    func offRentPanel(padding: CGFloat = Space.roomy) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.graphite, in: RoundedRectangle(cornerRadius: Radius.panel))
    }

    /// Rows sharing one card, divided by hairlines.
    func offRentGroup() -> some View {
        self
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(Palette.hairline, lineWidth: Layout.hairline)
            )
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    /// The page.
    func offRentScreen() -> some View {
        background(Palette.background.ignoresSafeArea())
    }

    /// The page, for a `Form` or a `List`.
    ///
    /// Hides the system's cool grouped background and paints the warm-white one under it, leaving
    /// the rows, separators, swipe actions and section behaviour exactly as the platform draws
    /// them. Most list-shaped screens in this app are real `List`s for that reason.
    func offRentFormBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Palette.background.ignoresSafeArea())
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
            .foregroundStyle(Palette.onAccent.opacity(isEnabled ? 1 : 0.45))
            // Disabled is the same button at a third strength, not a different grey shape. Filling
            // it with `sunken` made it read as a dead slab on the warm page — something switched
            // off rather than something waiting on one more field.
            .frame(maxWidth: .infinity, minHeight: Layout.controlHeight)
            .background(
                Palette.accent.opacity(isEnabled ? 1 : 0.32),
                in: RoundedRectangle(cornerRadius: Radius.control)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

/// The secondary action. Tinted text at a full-width tap target — no second outlined box
/// competing with the primary one, which is what made these screens feel busy.
struct OffRentSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(isEnabled ? Palette.accent : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: Layout.minimumTapTarget)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == OffRentPrimaryButtonStyle {
    static var offRentPrimary: OffRentPrimaryButtonStyle { OffRentPrimaryButtonStyle() }
}

extension ButtonStyle where Self == OffRentSecondaryButtonStyle {
    static var offRentSecondary: OffRentSecondaryButtonStyle { OffRentSecondaryButtonStyle() }
}
