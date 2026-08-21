import AppIntents
import SwiftUI

/// Shortcuts and Siri entry points.
///
/// Every one of them **opens the app to a place**. None of them writes a record.
///
/// That restraint is the point. "Record vendor confirmation" is the intent a user would most want
/// to run hands-free from a truck — and it is exactly the one that must not run hands-free,
/// because a confirmation created without the user affirming they contacted the vendor is a
/// fabricated piece of evidence sitting in their own ledger. The intent takes them to the sheet;
/// the sheet still requires the tick.
struct AddRentalIntent: AppIntent {
    static var title: LocalizedStringResource = "Add a rental"
    static var description = IntentDescription(
        "Opens \(AppConfiguration.displayName) ready to add a piece of rented equipment."
    )
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.pending = .addRental
        return .result()
    }
}

struct OpenActiveRentalsIntent: AppIntent {
    static var title: LocalizedStringResource = "Open active rentals"
    static var description = IntentDescription(
        "Opens \(AppConfiguration.displayName) to the rentals you still have on the ground."
    )
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        IntentRouter.shared.pending = .rentals
        return .result()
    }
}

struct RecordVendorConfirmationIntent: AppIntent {
    static var title: LocalizedStringResource = "Record a vendor confirmation"
    static var description = IntentDescription(
        """
        Opens \(AppConfiguration.displayName) to the confirmation screen. It does not record anything on its own — \
        you enter the confirmation number the rental company gave you, and confirm that you \
        contacted them.
        """
    )
    static var openAppWhenRun = true

    @Parameter(title: "Rental item")
    var item: RentalItemEntity?

    @MainActor
    func perform() async throws -> some IntentResult {
        if let item {
            IntentRouter.shared.pending = .recordConfirmation(itemID: item.id)
        } else {
            // No item chosen: land on the list rather than guessing which machine was meant.
            // Guessing here would put a confirmation sheet in front of the wrong rental.
            IntentRouter.shared.pending = .rentals
        }
        return .result()
    }
}

/// A rental item, as Shortcuts sees it.
struct RentalItemEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Rental item")
    static var defaultQuery = RentalItemQuery()

    var id: UUID
    var equipmentName: String
    var vendorName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(equipmentName)", subtitle: "\(vendorName)")
    }
}

/// Supplies rental items to Shortcuts.
///
/// Reads through the App Group snapshot's sibling: a small, separately published index of open
/// items. It deliberately does not open the SwiftData store from an out-of-process query, which
/// would risk contending with the app for the same file.
struct RentalItemQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [RentalItemEntity] {
        IntentItemIndex.read().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [RentalItemEntity] {
        IntentItemIndex.read()
    }
}

/// The open-item index the app publishes for Shortcuts.
///
/// Carries only what a Shortcuts picker has to show — the machine and who it is from. No rates, no
/// invoice figures, no confirmation numbers.
enum IntentItemIndex {
    private static let key = "com.idlery.offrent.intentItemIndex.v1"

    struct Entry: Codable, Sendable {
        var id: UUID
        var equipmentName: String
        var vendorName: String
    }

    static func publish(_ entries: [Entry]) {
        guard let defaults = UserDefaults(suiteName: SharedIdentifiers.appGroupIdentifier),
              let data = try? JSONEncoder().encode(entries)
        else { return }
        defaults.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults(suiteName: SharedIdentifiers.appGroupIdentifier)?.removeObject(forKey: key)
    }

    static func read() -> [RentalItemEntity] {
        guard let defaults = UserDefaults(suiteName: SharedIdentifiers.appGroupIdentifier),
              let data = defaults.data(forKey: key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return entries.map {
            RentalItemEntity(id: $0.id, equipmentName: $0.equipmentName, vendorName: $0.vendorName)
        }
    }
}

/// Carries an intent's destination into the running app.
///
/// A singleton, and the one place in the app that is. An `AppIntent` is constructed by the system
/// outside the SwiftUI environment, so it has no `AppRouter` to talk to; this holds the
/// destination just long enough for `RootView` to pick it up. It holds no business state.
@MainActor
final class IntentRouter {
    static let shared = IntentRouter()
    var pending: DeepLink?
    private init() {}

    func consume() -> DeepLink? {
        defer { pending = nil }
        return pending
    }
}

struct OffRentShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddRentalIntent(),
            phrases: [
                "Add a rental in \(.applicationName)",
                "New rental in \(.applicationName)",
            ],
            shortTitle: "Add rental",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: OpenActiveRentalsIntent(),
            phrases: [
                "Show my rentals in \(.applicationName)",
                "Open active rentals in \(.applicationName)",
            ],
            shortTitle: "Active rentals",
            systemImageName: "shippingbox"
        )
        AppShortcut(
            intent: RecordVendorConfirmationIntent(),
            phrases: [
                "Record a vendor confirmation in \(.applicationName)",
                "Log an off-rent confirmation in \(.applicationName)",
            ],
            shortTitle: "Record confirmation",
            systemImageName: "checkmark.rectangle.stack"
        )
    }
}
