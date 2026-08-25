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

    /// The accent as *text*, which is a different requirement from the accent as a fill.
    ///
    /// WCAG asks 3:1 of a non-text UI component and 4.5:1 of body text. `accent` is both in this
    /// app: it fills the primary button, and it is the label colour of every secondary one —
    /// Accept, Question, Record a follow-up, Reopen. As a label in light mode it measured 3.14:1
    /// on the page and 3.60:1 on a card, which is not a close call.
    ///
    /// Same hue, darkened until it clears 4.5:1 on the darkest light surface. Dark mode is the
    /// identical value: it already ran between 6.7 and 8.5, and darkening there would have made
    /// it worse.
    static let accentText = Color("AccentTextColor")

    /// Attention, not alarm. An item needing a phone call is not an error.
    static let attention = Color("AttentionColor")
    /// Attention as text. See `accentText`: 3.94:1 on the page as a label, and this is how
    /// an overdue rental describes itself.
    static let attentionText = Color("AttentionTextColor")
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

    /// The label on a control that is switched off.
    ///
    /// Not `.secondary`. `secondaryLabel` composites to 3.26:1 on the page, 3.44:1 on a card and
    /// 3.22:1 in a well — below the 4.5:1 that `check_text_colours_meet_contrast` holds every
    /// text colour in this palette to, and a control that is off still has to say what it is.
    /// The label colour at 65% measures 6.63 / 6.98 / 6.55 on those three light surfaces and
    /// 8.29 / 7.71 / 7.03 on the dark ones, by the same maths.
    static let disabledLabel = Color.primary.opacity(0.65)

    /// The border the reader gets when they have switched Increase Contrast on.
    ///
    /// The hairline is 1.21–1.63:1 against the surfaces it sits on, which is the whole point of
    /// it — the edge is meant to be felt rather than seen. Somebody who has asked the system for
    /// more contrast is asking for the opposite, so it becomes a real border: 3.85–3.98:1 in
    /// light and 4.80–5.33:1 in dark, clearing the 3:1 WCAG asks of a non-text component.
    private static let strongEdge = Color.primary.opacity(0.5)

    /// The edge of a surface — a card, a group, a well.
    static func edge(_ contrast: ColorSchemeContrast) -> Color {
        contrast == .increased ? strongEdge : hairline
    }

    /// The edge of a *filled* control, which normally draws none: its fill is its shape.
    static func fillEdge(_ contrast: ColorSchemeContrast) -> Color {
        contrast == .increased ? strongEdge : .clear
    }

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

    /// A hairline is a hairline until the reader asks for more contrast, at which point half a
    /// point more is the difference between an edge and a suggestion.
    static func edgeWidth(_ contrast: ColorSchemeContrast) -> CGFloat {
        contrast == .increased ? hairline * 1.5 : hairline
    }

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

    /// Reduce Motion, for the `withAnimation` call sites a view modifier cannot reach.
    ///
    /// `respectfulAnimation` is the declarative half of the same rule and is what a call site
    /// should reach for first; this exists for the imperative ones, which have to read
    /// `\.accessibilityReduceMotion` themselves and pass it in.
    ///
    /// The default replacement is `.default`, matching that modifier: motion becomes a
    /// cross-fade rather than disappearing, so the feedback survives. `travelling` says the
    /// animation *is* a journey across the screen — a map camera flying to a pin, a jump to a
    /// clause four pages down — where a gentler curve is still the movement the setting was
    /// switched on to avoid. Those are dropped outright.
    static func respecting(
        _ animation: Animation, reduceMotion: Bool, travelling: Bool = false
    ) -> Animation? {
        guard reduceMotion else { return animation }
        return travelling ? nil : .default
    }
}

// MARK: - Surface modifiers

extension View {

    /// A card: white, a hairline, and a shadow soft enough that you notice the edge rather than
    /// the shadow. No stacked shadows, no gradient — this has to stay legible in bright sun.
    func offRentCard(padding: CGFloat = Space.comfortable,
                     radius: CGFloat = Radius.card) -> some View {
        modifier(OffRentCard(padding: padding, radius: radius))
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
        modifier(OffRentGroup())
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

/// The card and the group are modifiers rather than plain chains for one reason: they are the
/// only two places in the app that draw a surface edge, so reading `\.colorSchemeContrast` here
/// makes every card, every row group and every screen built out of them honour Increase Contrast
/// at once. A `View` extension cannot read the environment; a `ViewModifier` can.
private struct OffRentCard: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    let padding: CGFloat
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Palette.edge(contrast), lineWidth: Layout.edgeWidth(contrast))
            )
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

private struct OffRentGroup: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(Palette.edge(contrast), lineWidth: Layout.edgeWidth(contrast))
            )
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
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
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            // Disabled is the same button at reduced strength, not a different grey shape.
            // Filling it with `sunken` made it read as a dead slab on the warm page — something
            // switched off rather than something waiting on one more field.
            //
            // The label is the system label colour rather than a faded `onAccent`, because
            // `onAccent` is a fixed graphite: over a washed-out fill it measured 2.60:1 in light
            // and 1.30:1 in dark, and no amount of opacity fixes the dark case — the fill there
            // is *darker* than the text. The label colour flips with the scheme and lands at
            // 10.85–12.09:1 in light and 6.39–7.77:1 in dark, all clear of the 4.5:1 bar. The
            // fill itself is at 45% rather than 32% so the switched-off control still has a
            // shape in sunlight; a fill that reached 3:1 would not read as switched off at all,
            // and WCAG 1.4.3 exempts an inactive component from that bar in any case.
            .foregroundStyle(isEnabled ? Palette.onAccent : Color.primary)
            .frame(maxWidth: .infinity, minHeight: Layout.controlHeight)
            .background(
                Palette.accent.opacity(isEnabled ? 1 : 0.45),
                in: RoundedRectangle(cornerRadius: Radius.control)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control)
                    .strokeBorder(
                        Palette.fillEdge(contrast), lineWidth: Layout.edgeWidth(contrast)
                    )
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .respectfulAnimation(Motion.quick, value: configuration.isPressed)
    }
}

/// The secondary action. Tinted text at a full-width tap target — no second outlined box
/// competing with the primary one, which is what made these screens feel busy.
struct OffRentSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            // `.secondary` was 3.22–3.44:1 on the three light surfaces. `Palette.disabledLabel`
            // is the same idea — a grey that says "not now" — measured rather than assumed, at
            // 6.55:1 or better everywhere.
            .foregroundStyle(isEnabled ? Palette.accentText : Palette.disabledLabel)
            .frame(maxWidth: .infinity, minHeight: Layout.minimumTapTarget)
            // No box normally: a second outlined shape competing with the primary button is what
            // made these screens feel busy. Increase Contrast is the one case where the reader
            // has explicitly asked for the box.
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control)
                    .strokeBorder(
                        Palette.fillEdge(contrast), lineWidth: Layout.edgeWidth(contrast)
                    )
            )
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.55 : 1)
            .respectfulAnimation(Motion.quick, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == OffRentPrimaryButtonStyle {
    static var offRentPrimary: OffRentPrimaryButtonStyle { OffRentPrimaryButtonStyle() }
}

extension ButtonStyle where Self == OffRentSecondaryButtonStyle {
    static var offRentSecondary: OffRentSecondaryButtonStyle { OffRentSecondaryButtonStyle() }
}
