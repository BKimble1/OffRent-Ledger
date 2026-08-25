import Foundation
import XCTest
@testable import OffRentDomain

/// "It should auto scan and fill if you allow it" — and the three conditions on *allow*.
final class ScanSettingsTests: XCTestCase {

    /// On by default now: the scanner's best behaviour was the one nobody saw.
    ///
    /// The guards are what make that safe, and they are asserted individually below — three
    /// fields minimum, and nothing on the page read at less than full confidence.
    func testTheShortcutIsOnByDefault() {
        XCTAssertTrue(ScanSettings.default.autoFillConfidentScans)
        XCTAssertTrue(
            ScanSettings.default.shouldFillAutomatically(preselectedCount: 9, hasAnythingUnticked: false)
        )
    }

    /// And it can still be switched off, which is the whole point of it being a setting.
    func testTurningItOffStopsEveryShortcut() {
        let settings = ScanSettings(autoFillConfidentScans: false)
        XCTAssertFalse(
            settings.shouldFillAutomatically(preselectedCount: 9, hasAnythingUnticked: false),
            "a scan as clear as this one still stops at the review screen when the user said to"
        )
    }

    func testAClearScanWithTheSettingOnGoesStraightToTheForm() {
        let settings = ScanSettings(autoFillConfidentScans: true)
        XCTAssertTrue(settings.shouldFillAutomatically(preselectedCount: 9, hasAnythingUnticked: false))
    }

    func testAnythingReadAtMediumConfidenceStopsTheShortcut() {
        // The condition that matters. A scan that is part confident and part uncertain is
        // precisely the one worth looking at, so the shortcut stands down rather than quietly
        // dropping the uncertain half.
        let settings = ScanSettings(autoFillConfidentScans: true)
        XCTAssertFalse(
            settings.shouldFillAutomatically(preselectedCount: 9, hasAnythingUnticked: true)
        )
    }

    func testAThinScanStillStopsSoTheFormDoesNotLookBroken() {
        // One field filled in, arrived at without the user seeing the scan do anything, looks
        // like the scan failed.
        let settings = ScanSettings(autoFillConfidentScans: true)
        XCTAssertFalse(settings.shouldFillAutomatically(preselectedCount: 2, hasAnythingUnticked: false))
        XCTAssertTrue(settings.shouldFillAutomatically(preselectedCount: 3, hasAnythingUnticked: false))
    }

    func testTheSettingSurvivesARoundTrip() {
        let defaults = UserDefaults(suiteName: "ScanSettingsTests")!
        defaults.removePersistentDomain(forName: "ScanSettingsTests")
        XCTAssertTrue(
            ScanSettingsStore.load(from: defaults).autoFillConfidentScans,
            "an empty store reads as the default, which is on"
        )
        ScanSettingsStore.save(ScanSettings(autoFillConfidentScans: false), to: defaults)
        XCTAssertFalse(
            ScanSettingsStore.load(from: defaults).autoFillConfidentScans,
            "and a user who switched it off keeps it off across launches"
        )
    }
}
