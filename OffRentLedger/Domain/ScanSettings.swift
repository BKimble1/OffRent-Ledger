import Foundation

/// What the scanner is allowed to do without being asked each time.
///
/// One setting, on by default, and switchable in Settings.
///
/// It shipped off, which meant the scanner's best behaviour was the one nobody saw. Turning it on
/// does not change *what* is applied — only high-confidence suggestions ever were — and it does
/// not write anything: the values land in the rental form, and the form still has to be saved.
/// What it skips is a confirmation screen on a scan the app has no uncertainty about at all.
///
/// The guards below are what make that safe, and they are strict on purpose: three fields
/// minimum, and not one thing on the page read at less than full confidence.
struct ScanSettings: Codable, Sendable, Equatable {

    /// Skip the review screen when a scan is clear enough to stand on its own.
    var autoFillConfidentScans: Bool

    /// How many high-confidence fields a scan must produce before it can skip the review.
    ///
    /// Three, not one. A scan that reads only the agreement number has told the user almost
    /// nothing, and jumping them straight back to a form with one box filled looks like the scan
    /// failed. Three is the point at which the form visibly did some work.
    static let minimumFieldsForAutoFill = 3

    init(autoFillConfidentScans: Bool = true) {
        self.autoFillConfidentScans = autoFillConfidentScans
    }

    static let `default` = ScanSettings()

    /// Whether *this* scan qualifies, given what it found.
    ///
    /// Deliberately a function of the outcome rather than of the screen, so the rule is one
    /// sentence in one place and the test does not need a view.
    func shouldFillAutomatically(preselectedCount: Int, hasAnythingUnticked: Bool) -> Bool {
        guard autoFillConfidentScans else { return false }
        guard preselectedCount >= Self.minimumFieldsForAutoFill else { return false }
        // Something read at medium confidence is something the user should look at. A scan that
        // is part confident and part uncertain is precisely the one worth reviewing, so the
        // shortcut stands down rather than quietly dropping the uncertain half.
        return !hasAnythingUnticked
    }
}

/// Reads and writes `ScanSettings`. Mirrors `ReminderSettingsStore`.
enum ScanSettingsStore {
    static let defaultsKey = "com.idlery.offrent.scanSettings.v1"

    static func load(from defaults: UserDefaults = .standard) -> ScanSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(ScanSettings.self, from: data)
        else { return .default }
        return settings
    }

    static func save(_ settings: ScanSettings, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}
