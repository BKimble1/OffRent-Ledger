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

    /// Set when the app has a snapshot to give but the entitlement to see it has lapsed.
    ///
    /// A separate key rather than a field on the snapshot, so a withheld state carries no
    /// counts and no figure at all — the widget cannot leak what it was not allowed to show,
    /// even by accident.
    static let snapshotWithheldDefaultsKey = "com.idlery.offrent.summarySnapshot.withheld.v1"

    static let widgetKind = "OffRentLedgerSummaryWidget"

    /// The Control Centre / Action Button control.
    static let quickAddControlKind = "OffRentLedgerQuickAddControl"
}
