import Foundation
import SwiftUI
import UIKit

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

/// The app's palette, restated in code.
///
/// The widget extension does not compile `OffRentLedger/Resources/Assets.xcassets`, and a named
/// colour that is not in the bundle fails silently at render time rather than loudly at build
/// time — the widget would simply draw black. These are the same sRGB components as
/// `AccentColor`, `AttentionColor`, `WaitingColor` and `SettledColor` in that catalog; if one of
/// those changes, change it here too. `scripts/verify_repository.py` checks the pair still match.
enum WidgetPalette {

    /// Warm amber. The app's accent, and deliberately not anybody else's blue.
    static let accent = dynamic(
        light: (0.847, 0.400, 0.086),
        dark: (0.949, 0.541, 0.212)
    )

    /// Something needs a phone call or a charge needs checking.
    static let attention = dynamic(
        light: (0.784, 0.318, 0.055),
        dark: (0.964, 0.596, 0.278)
    )

    /// Waiting on somebody else. Muted on purpose — it is not an action.
    static let waiting = dynamic(
        light: (0.310, 0.396, 0.478),
        dark: (0.573, 0.663, 0.749)
    )

    /// Recorded and settled.
    static let settled = dynamic(
        light: (0.196, 0.471, 0.318),
        dark: (0.400, 0.749, 0.541)
    )

    private static func dynamic(
        light: (Double, Double, Double),
        dark: (Double, Double, Double)
    ) -> Color {
        Color(
            uiColor: UIColor { traits in
                let components = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(
                    red: components.0, green: components.1, blue: components.2, alpha: 1
                )
            }
        )
    }
}
