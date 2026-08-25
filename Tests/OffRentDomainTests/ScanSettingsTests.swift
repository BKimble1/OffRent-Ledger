import Foundation
import XCTest
@testable import OffRentDomain

/// "It should auto scan and fill if you allow it" — and the three conditions on *allow*.
final class ScanSettingsTests: XCTestCase {

    func testTheShortcutIsOffUntilItIsTurnedOn() {
        XCTAssertFalse(ScanSettings.default.autoFillConfidentScans)
        XCTAssertFalse(
            ScanSettings.default.shouldFillAutomatically(preselectedCount: 9, hasAnythingUnticked: false),
            "a clear scan still stops at the review screen until the user opts in"
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
        XCTAssertFalse(ScanSettingsStore.load(from: defaults).autoFillConfidentScans)
        ScanSettingsStore.save(ScanSettings(autoFillConfidentScans: true), to: defaults)
        XCTAssertTrue(ScanSettingsStore.load(from: defaults).autoFillConfidentScans)
    }
}
