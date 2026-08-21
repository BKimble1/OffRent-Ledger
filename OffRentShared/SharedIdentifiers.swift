import Foundation

/// Identifiers that the app and the widget extension must agree on exactly.
///
/// This file is compiled into both targets. Changing a value here changes it in both places at
/// once, which is the only way an App Group ever stays in sync — a widget reading a different key
/// than the app writes shows stale data forever and never errors.
enum SharedIdentifiers {

    /// Must match the App Group capability on both targets' entitlements.
    static let appGroupIdentifier = "group.com.idlery.offrent"

    /// Must match `CFBundleURLSchemes` in the app's Info.plist.
    static let urlScheme = "offrent"

    /// Versioned on purpose. If the snapshot shape changes, bump the key rather than reusing it:
    /// a widget from the previous app version may still be alive and decoding the old shape.
    static let snapshotDefaultsKey = "com.idlery.offrent.summarySnapshot.v1"

    static let widgetKind = "OffRentLedgerSummaryWidget"
}
