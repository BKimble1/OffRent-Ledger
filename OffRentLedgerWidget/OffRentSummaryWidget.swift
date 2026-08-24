import SwiftUI
import WidgetKit

/// A glanceable summary of what is running and what needs attention.
///
/// It reads a snapshot the app wrote to the App Group. It never opens the SwiftData store, which
/// means a widget refresh cannot migrate it, lock it against the app, or fail in a way anybody has
/// to debug — and it means the widget is structurally unable to display a vendor name, a jobsite,
/// a machine or an invoice amount, because `RentalSummarySnapshot` has nowhere to put them.
struct OffRentSummaryWidget: Widget {

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedIdentifiers.widgetKind, provider: SummaryProvider()) { entry in
            SummaryWidgetView(entry: entry)
        }
        .configurationDisplayName("OffRent Summary")
        .description("Estimated rent running, what needs a vendor call, and the next rate change.")
        // The accessory families are the reason `RentalSummarySnapshot` carries counts and one
        // aggregate figure and nothing else. A lock screen is read by whoever picks the phone
        // up, so there is deliberately no field here that could name a machine, a jobsite or a
        // rental company — the guarantee is structural rather than a rule to remember.
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryRectangular, .accessoryCircular, .accessoryInline,
        ])
    }
}

struct SummaryEntry: TimelineEntry {
    let date: Date
    let snapshot: RentalSummarySnapshot?
    /// True when the app has never published, which is also what a free user's widget shows.
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
                snapshot: snapshot ?? (context.isPreview ? .placeholder(now: Date()) : nil),
                isPlaceholder: snapshot == nil
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
        let snapshot = SnapshotReader.read()
        let entry = SummaryEntry(date: Date(), snapshot: snapshot, isPlaceholder: snapshot == nil)

        // Refreshed hourly. The figure only changes when a billing day rolls over, so anything
        // more frequent spends the widget's refresh budget to redraw the same number.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3_600)
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

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, !entry.isPlaceholder {
                switch family {
                case .accessoryInline: inlineAccessory(snapshot)
                case .accessoryCircular: circularAccessory(snapshot)
                case .accessoryRectangular: rectangularAccessory(snapshot)
                default: content(snapshot)
                }
            } else {
                emptyState
            }
        }
        .containerBackground(for: .widget) {
            // An accessory widget is drawn onto the wallpaper and must not paint a panel behind
            // itself; a home screen one should.
            if isAccessory {
                Color.clear
            } else {
                // A system material rather than a named colour: the widget extension does not
                // compile the app's asset catalog, and a missing named colour fails silently at
                // render time rather than loudly at build time.
                Color.clear.background(.fill.tertiary)
            }
        }
    }

    // MARK: - Lock screen

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

    @ViewBuilder
    private func content(_ snapshot: RentalSummarySnapshot) -> some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 4 : 8) {
            Text("Estimated rent running")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(Formatters.currencyRounded(snapshot.estimatedRentRunning))
                .font(family == .systemSmall ? .title3 : .title2)
                .fontWeight(.semibold)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text("Estimate")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if family == .systemMedium || family == .systemLarge {
                HStack(spacing: 14) {
                    stat("\(snapshot.openItemCount)", "open")
                    stat("\(snapshot.awaitingPickupCount)", "awaiting pickup")
                    stat("\(snapshot.invoicesAwaitingReviewCount)", "to review")
                }
            } else {
                stat("\(snapshot.openItemCount)", snapshot.openItemCount == 1 ? "open rental" : "open rentals")
            }

            if family == .systemLarge {
                Divider()
                // The large family has room to say what to do next rather than only what is
                // true. Still aggregate — it names no machine and no rental company.
                Text(nextStepLine(snapshot))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text("Tap to open \(SharedBranding.displayName)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let next = snapshot.nextRateChangeDate {
                Text("Next rate change \(next.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(DeepLink.today.url)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription(snapshot))
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
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.headline).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "shippingbox")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(SharedBranding.displayName)
                .font(.caption)
                .fontWeight(.medium)
            Text("Open the app to start tracking a rental.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(DeepLink.today.url)
        .accessibilityLabel("\(SharedBranding.displayName). Open the app to start tracking a rental.")
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
