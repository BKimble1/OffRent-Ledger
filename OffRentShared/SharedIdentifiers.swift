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
    static let snapshotDefaultsKey = "com.idlery.offrent.summarySnapshot.v2"

    /// Keys this app used to write. `AppGroupSnapshotPublisher` removes them on every publish, so
    /// an App Group upgraded from an older build does not keep a blob nothing will ever read
    /// again. Delete an entry here only once no shipped build can still be installed with it.
    static let retiredSnapshotDefaultsKeys = [
        "com.idlery.offrent.summarySnapshot.v1",
        // The widget used to be a Pro feature and this flag said so. It is not one any more:
        // entitlement gates creating rentals, never seeing the ones you already have.
        "com.idlery.offrent.summarySnapshot.withheld.v1",
    ]

    static let widgetKind = "OffRentLedgerSummaryWidget"

    /// The Control Centre / Action Button control.
    static let quickAddControlKind = "OffRentLedgerQuickAddControl"
}
