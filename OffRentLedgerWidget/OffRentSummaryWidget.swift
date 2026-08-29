import SwiftUI
import WidgetKit

/// A glanceable summary of what is on rent and what needs attention.
///
/// It reads a snapshot the app wrote to the App Group. It never opens the SwiftData store, which
/// means a widget refresh cannot migrate it, lock it against the app, or fail in a way anybody has
/// to debug — and it means the widget is structurally unable to display a rental company, a
/// jobsite, an address, an agreement number or an invoice amount, because `RentalSummarySnapshot`
/// has nowhere to put them.
struct OffRentSummaryWidget: Widget {

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedIdentifiers.widgetKind, provider: SummaryProvider()) { entry in
            SummaryWidgetView(entry: entry)
        }
        .configurationDisplayName("OffRent Summary")
        .description("What is on rent, what it is running to, and what needs a call.")
        .supportedFamilies([
            // `.systemExtraLarge` is the iPad-only home screen family. It is listed because the
            // app is universal and an iPad home screen offers it; WidgetKit simply never offers
            // it on an iPhone.
            .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
            .accessoryRectangular, .accessoryCircular, .accessoryInline,
        ])
        .contentMarginsDisabled()
    }
}

struct SummaryEntry: TimelineEntry {
    let date: Date
    let snapshot: RentalSummarySnapshot?
    /// True when the app has never published anything, so the sample data is showing.
    let isPlaceholder: Bool
}

struct SummaryProvider: TimelineProvider {

    func placeholder(in context: Context) -> SummaryEntry {
        SummaryEntry(date: Date(), snapshot: .placeholder(now: Date()), isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SummaryEntry) -> Void) {
        let snapshot = SnapshotReader.read()
        completion(
            SummaryEntry(
                date: Date(),
                // The gallery preview always shows something worth looking at, so a user
                // deciding whether to add the widget sees the feature rather than an empty box.
                snapshot: snapshot ?? (context.isPreview ? .placeholder(now: Date()) : nil),
                isPlaceholder: snapshot == nil
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
        let snapshot = SnapshotReader.read()
        let entry = SummaryEntry(date: Date(), snapshot: snapshot, isPlaceholder: snapshot == nil)

        // Refreshed hourly. The figure only moves when a billing day rolls over, so anything more
        // frequent spends the widget's refresh budget redrawing the same number. Every change the
        // user makes in the app calls `WidgetCenter.reloadTimelines` anyway, so this is the floor
        // rather than the only way the widget ever updates.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date())
            ?? Date().addingTimeInterval(3_600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct SummaryWidgetView: View {
    let entry: SummaryEntry
    @Environment(\.widgetFamily) private var family

    private var isAccessory: Bool {
        switch family {
        case .accessoryRectangular, .accessoryCircular, .accessoryInline: true
        default: false
        }
    }

    /// How many rentals this family has room for.
    ///
    /// Zero for the lock screen, and that zero is the privacy guarantee: the accessory branches
    /// below never read `snapshot.rows` at all, so a machine name cannot reach a surface that is
    /// legible to whoever picks the phone up. `scripts/verify_repository.py` fails the build if
    /// one of them starts to.
    private var rowCapacity: Int {
        switch family {
        case .systemSmall: 2
        case .systemMedium: 3
        case .systemLarge: 6
        case .systemExtraLarge: 8
        default: 0
        }
    }

    /// The families wide enough to put the amount on the same line as the machine.
    private var isWide: Bool {
        switch family {
        case .systemMedium, .systemLarge, .systemExtraLarge: true
        default: false
        }
    }

    /// The families with room to say what to do next underneath the rentals.
    private var hasRoomForTheNextStep: Bool {
        switch family {
        case .systemLarge, .systemExtraLarge: true
        default: false
        }
    }

    /// Whether there is height left for anything after the rentals.
    ///
    /// `.systemSmall` is 155pt square, and 14 of padding on each side leaves 127. The header is
    /// about 35 of that and two stacked rows about 61, which with the divider and the gaps is
    /// already 113. A "+2 more" line and a "Next rate change" line under that do not fit — they
    /// push the last row into the edge of the widget, and what a small widget then shows is a
    /// clipped rental. The small family gets the figure and the machines and stops there, which
    /// is what a small widget is for.
    private var showsSecondaryLines: Bool { family != .systemSmall }

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                switch family {
                case .accessoryInline: inlineAccessory(snapshot)
                case .accessoryCircular: circularAccessory(snapshot)
                case .accessoryRectangular: rectangularAccessory(snapshot)
                default:
                    if snapshot.rows.isEmpty && snapshot.isEmpty {
                        nothingOpenState
                    } else {
                        content(snapshot)
                    }
                }
            } else {
                emptyState
            }
        }
        .padding(isAccessory ? 0 : 14)
        // At the root, so every family links the same way, and so the parts of a home screen
        // widget that are not one of the per-rental `Link`s still open the app.
        .widgetURL(DeepLink.today.url)
        .containerBackground(for: .widget) {
            // An accessory widget is drawn onto the wallpaper and must not paint a panel behind
            // itself; a home screen one should.
            if isAccessory {
                Color.clear
            } else {
                background
            }
        }
    }

    /// A system fill with a wash of the app's amber across the top corner.
    ///
    /// System materials rather than a named colour: the widget extension does not compile the
    /// app's asset catalog, and a missing named colour fails silently at render time rather than
    /// loudly at build time. `WidgetPalette` is the one exception and states its own components.
    private var background: some View {
        ZStack {
            Color.clear.background(.fill.tertiary)
            LinearGradient(
                colors: [WidgetPalette.accent.opacity(0.16), WidgetPalette.accent.opacity(0.02)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    // MARK: - Lock screen
    //
    // Counts, one aggregate figure, one date. Never `snapshot.rows`.

    private func inlineAccessory(_ snapshot: RentalSummarySnapshot) -> some View {
        Text("\(Formatters.currencyRounded(snapshot.estimatedRentRunning)) running")
            .accessibilityLabel(
                "Estimated rent running, \(Formatters.currencyAccessible(snapshot.estimatedRentRunning))"
            )
    }

    private func circularAccessory(_ snapshot: RentalSummarySnapshot) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text("\(snapshot.openItemCount)")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("open")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(
            "\(snapshot.openItemCount) open \(snapshot.openItemCount == 1 ? "rental" : "rentals")"
        )
    }

    private func rectangularAccessory(_ snapshot: RentalSummarySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Estimated rent running")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(Formatters.currencyRounded(snapshot.estimatedRentRunning))
                .font(.headline)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(attentionLine(snapshot))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription(snapshot))
    }

    /// One line for the small surfaces: the thing most worth doing, or how many are running.
    private func attentionLine(_ snapshot: RentalSummarySnapshot) -> String {
        if snapshot.invoicesAwaitingReviewCount > 0 {
            return "\(snapshot.invoicesAwaitingReviewCount) to review"
        }
        if snapshot.awaitingPickupCount > 0 {
            return "\(snapshot.awaitingPickupCount) awaiting pickup"
        }
        return "\(snapshot.openItemCount) open \(snapshot.openItemCount == 1 ? "rental" : "rentals")"
    }

    // MARK: - Home screen

    @ViewBuilder
    private func content(_ snapshot: RentalSummarySnapshot) -> some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 10) {
            header(snapshot)

            let shown = Array(snapshot.rows.prefix(rowCapacity))
            if !shown.isEmpty {
                Divider().opacity(0.6)
                if family == .systemExtraLarge {
                    // Double width, so two columns of rentals rather than one very long line.
                    let half = (shown.count + 1) / 2
                    HStack(alignment: .top, spacing: 22) {
                        rowStack(Array(shown.prefix(half)))
                        rowStack(Array(shown.dropFirst(half)))
                    }
                } else {
                    rowStack(shown)
                }
            }

            let hidden = snapshot.openItemCount - shown.count
            if hidden > 0, showsSecondaryLines {
                Text("+\(hidden) more in the app")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if hasRoomForTheNextStep {
                Divider().opacity(0.6)
                // Room to say what to do next rather than only what is true. Still names no
                // rental company: the instruction is to the user, about the user's own record.
                Text(nextStepLine(snapshot))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let next = snapshot.nextRateChangeDate, showsSecondaryLines {
                Text("Next rate change \(next.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func rowStack(_ rows: [RentalSummarySnapshot.Row]) -> some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 5 : 7) {
            ForEach(rows) { row in
                rentalRow(row)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The aggregate, and — where there is width for it — the three counts beside it.
    private func header(_ snapshot: RentalSummarySnapshot) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Estimated rent running")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(Formatters.currencyRounded(snapshot.estimatedRentRunning))
                    .font(family == .systemSmall ? .title3 : .title2)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(WidgetPalette.accent)
            }
            if isWide {
                Spacer(minLength: 8)
                HStack(spacing: 14) {
                    stat("\(snapshot.openItemCount)", "open")
                    stat("\(snapshot.awaitingPickupCount)", "pickup")
                    stat("\(snapshot.invoicesAwaitingReviewCount)", "review")
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription(snapshot))
    }

    /// One rental: a status dot, the machine, and what it has run to.
    ///
    /// A `Link` rather than plain text, so a tap opens *that* rental instead of the app's Today
    /// tab. WidgetKit ignores `Link` on `.systemSmall` — that family is one tap target and falls
    /// back to the root `widgetURL`, which is the right destination for it anyway.
    @ViewBuilder
    private func rentalRow(_ row: RentalSummarySnapshot.Row) -> some View {
        if let url = DeepLink.rentalItem(id: row.id).url {
            Link(destination: url) { rentalRowBody(row) }
        } else {
            rentalRowBody(row)
        }
    }

    private func rentalRowBody(_ row: RentalSummarySnapshot.Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            // A view with no text in it takes its bottom edge as its first text baseline, which
            // is what puts the dot on the name's baseline rather than through the middle of it.
            Circle()
                .fill(dotColor(row.state))
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 0) {
                Text(row.machine)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !isWide {
                    Text(subtitle(row))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if isWide {
                Text(subtitle(row))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }

            // Only ever drawn when the rate engine produced a figure. A `$0` beside a machine
            // that has been on rent a week would read as "this one is free".
            if let estimate = row.estimate {
                Text(Formatters.currencyRounded(estimate))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowAccessibilityLabel(row))
    }

    /// Status, plus how long it has been out when that is known.
    private func subtitle(_ row: RentalSummarySnapshot.Row) -> String {
        guard let days = row.daysOnRent, row.state.isAccruing else { return row.state.shortLabel }
        return "\(row.state.shortLabel) · \(days) \(days == 1 ? "day" : "days")"
    }

    private func rowAccessibilityLabel(_ row: RentalSummarySnapshot.Row) -> String {
        var parts = [row.machine + ".", row.state.spokenLabel + "."]
        if let days = row.daysOnRent, row.state.isAccruing {
            parts.append("\(days) \(days == 1 ? "day" : "days") on rent.")
        }
        if let estimate = row.estimate {
            parts.append("Estimated \(Formatters.currencyAccessible(estimate)).")
        }
        return parts.joined(separator: " ")
    }

    /// Colour is never the only carrier of status — every row spells the status out beside it.
    private func dotColor(_ state: RentalSummarySnapshot.Row.State) -> Color {
        switch state {
        case .invoiceReview, .contactVendor, .needsFollowUp: WidgetPalette.attention
        case .accruing, .draft: WidgetPalette.accent
        case .awaitingPickup, .awaitingInvoice: WidgetPalette.waiting
        case .confirmationRecorded, .pickedUp: WidgetPalette.settled
        }
    }

    private func nextStepLine(_ snapshot: RentalSummarySnapshot) -> String {
        if snapshot.invoicesAwaitingReviewCount > 0 {
            return "An invoice is waiting to be checked against the terms you confirmed."
        }
        if snapshot.awaitingPickupCount > 0 {
            return "Something is off rent and still on site. Record the pickup once it is collected."
        }
        if let next = snapshot.nextRateChangeDate {
            return "The next rate change you confirmed is \(next.formatted(.dateTime.month(.abbreviated).day()))."
        }
        return "Nothing needs a phone call right now."
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    // MARK: - Nothing to show

    /// No snapshot at all: either the app has never run, or it could not reach the App Group.
    private var emptyState: some View {
        placeholderState(
            symbol: "shippingbox",
            message: "Open the app to start tracking a rental."
        )
    }

    /// The app published a snapshot and it says nothing is open.
    ///
    /// Separate from `emptyState` because that one means the widget could not read anything at
    /// all, and "open the app" is the right advice for that and the wrong advice for somebody who
    /// has the app open and has simply closed out every rental they had.
    private var nothingOpenState: some View {
        placeholderState(
            symbol: "checkmark.circle",
            message: "Nothing on rent right now. Add a rental to start tracking it."
        )
    }

    private func placeholderState(symbol: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(WidgetPalette.accent)
            Text(SharedBranding.displayName)
                .font(.caption)
                .fontWeight(.medium)
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(SharedBranding.displayName). \(message)")
    }

    private func accessibilityDescription(_ snapshot: RentalSummarySnapshot) -> String {
        var parts = [
            "Estimated rent running, \(Formatters.currencyAccessible(snapshot.estimatedRentRunning)).",
            "\(snapshot.openItemCount) open \(snapshot.openItemCount == 1 ? "rental" : "rentals").",
        ]
        if snapshot.awaitingPickupCount > 0 {
            parts.append("\(snapshot.awaitingPickupCount) awaiting pickup.")
        }
        if snapshot.invoicesAwaitingReviewCount > 0 {
            parts.append("\(snapshot.invoicesAwaitingReviewCount) to review.")
        }
        return parts.joined(separator: " ")
    }
}
