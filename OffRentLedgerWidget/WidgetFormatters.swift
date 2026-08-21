import Foundation

/// The widget compiles `OffRentShared` but not the app's `Services` folder, so it needs its own
/// copy of the two formatting helpers it uses. Deliberately tiny: anything larger belongs in
/// `OffRentShared` where both targets get one definition.
enum Formatters {
    static func currencyRounded(_ value: Decimal) -> String {
        value.formatted(
            .currency(code: "USD").locale(Locale(identifier: "en_US")).precision(.fractionLength(0))
        )
    }

    static func currencyAccessible(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: value as NSDecimalNumber) ?? currencyRounded(value)
    }
}

/// The widget reads the App Group snapshot directly rather than linking the app's service layer.
enum SnapshotReader {
    static func read() -> RentalSummarySnapshot? {
        guard let defaults = UserDefaults(suiteName: SharedIdentifiers.appGroupIdentifier),
              let data = defaults.data(forKey: SharedIdentifiers.snapshotDefaultsKey)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(RentalSummarySnapshot.self, from: data),
              snapshot.schemaVersion == RentalSummarySnapshot.currentSchemaVersion
        else { return nil }
        return snapshot
    }
}
