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
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("OffRent Summary")
        .description("Estimated rent running, what needs a vendor call, and the next rate change.")
        .supportedFamilies([.systemSmall, .systemMedium])
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

    var body: some View {
        if let snapshot = entry.snapshot, !entry.isPlaceholder {
            content(snapshot)
        } else {
            emptyState
        }
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

            if family == .systemMedium {
                HStack(spacing: 14) {
                    stat("\(snapshot.openItemCount)", "open")
                    stat("\(snapshot.awaitingPickupCount)", "awaiting pickup")
                    stat("\(snapshot.invoicesAwaitingReviewCount)", "to review")
                }
            } else {
                stat("\(snapshot.openItemCount)", snapshot.openItemCount == 1 ? "open rental" : "open rentals")
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
