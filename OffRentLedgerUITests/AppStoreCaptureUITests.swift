import Foundation
import XCTest

/// Drives the app to the six screens the App Store gallery is built from, and photographs them.
///
/// This is not a correctness test and it asserts almost nothing. It exists so that the screenshots
/// in `marketing/AppStore/` come out of a running app rather than out of a drawing program, and so
/// that producing them again — after a copy change, a redesign, or a new build — is one command
/// rather than an afternoon.
///
/// **What it produces.** Six PNGs, attached to the result bundle with the exact names the
/// placement guide asks for. `scripts/capture_appstore_screenshots.sh` runs this and extracts
/// them into `marketing/screenshots/`.
///
/// **What it cannot produce.** The seventh opening — template 2's front device — is a real iOS
/// Home Screen with the OffRent Summary widget on it. XCUITest cannot add a widget to a Home
/// Screen, and drawing one would put a picture of an iOS feature in an App Store listing. That
/// one is captured by hand; `marketing/screenshots/README.md` is the procedure.
///
/// **Why it runs in CI.** Because a capture path nobody exercises is a capture path that has
/// quietly stopped working by the time somebody needs it — which is the whole argument of
/// `verify_repository.check_every_ui_suite_actually_runs`. On a CI simulator the screenshots are
/// the wrong size and the map has no tiles; that does not matter, because what is under test here
/// is that all six screens can still be reached.
final class AppStoreCaptureUITests: XCTestCase {

    // MARK: - The knobs

    /// How far to drag a scrollable screen before photographing it, as a fraction of the window.
    ///
    /// Named constants rather than "swipe until something appears": a capture has to land in the
    /// same place every time, and "until it is on screen" lands wherever the last swipe stopped.
    /// If a screen's content changes and one of these puts the wrong part of it in frame, change
    /// the number here — that is the whole adjustment, and it is recorded in the diff.
    private enum Scroll {
        /// The confirmed rental's detail: past the summary, the next step and the terms, so the
        /// Off-rent confirmation block — number, who said it, meter, fuel, condition — is the
        /// thing the screenshot is of.
        static let offRentProof = 3
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    // MARK: - The capture

    func testCaptureTheAppStoreGallery() {
        let app = XCUIApplication.launchedForAppStoreCapture()

        // 1 — Today. The running figure, the counts, the rate change and the map card.
        app.expect(app.anyElement(A11yUI.Today.root))
        app.expect(app.staticTexts[A11yUI.Today.estimatedRentRunning])
        settle()
        capture(app, named: "appstore-01-today")

        // 2 — the in-app half of the widget frame. The machines behind the widget's total.
        app.tab(A11yUI.Tab.rentals).tap()
        app.expect(app.anyElement(A11yUI.Rentals.root))
        settle()
        capture(app, named: "appstore-02-rentals")

        // 3 — the evidence. A rental the vendor has confirmed off rent, scrolled to the proof.
        app.openRental(named: "Articulating Boom Lift")
        app.expect(app.anyElement(A11yUI.ItemDetail.root))
        for _ in 0..<Scroll.offRentProof { drag(app) }
        settle()
        capture(app, named: "appstore-03-off-rent-proof")
        app.back()

        // 4 — the map, with one machine's Awaiting Pickup card open on it.
        captureTheMap(app)

        // 5 — Scan Review, over the real pipeline. See `-offrent-open-scan-review`.
        captureTheScanReview(app)

        // 6 — the invoice, and the difference between what was expected and what was billed.
        app.tab(A11yUI.Tab.audit).tap()
        app.expect(app.anyElement(A11yUI.Audit.root))
        app.openInvoice(from: "Summit Rental Co.")
        app.expect(app.staticTexts[A11yUI.Audit.possibleVariance])
        settle()
        capture(app, named: "appstore-06-invoice-review")
    }

    // MARK: - The two that need steering

    private func captureTheMap(_ app: XCUIApplication) {
        app.tab(A11yUI.Tab.today).tap()
        app.tapInContent(app.anyElement(A11yUI.Today.map))
        app.expect(app.anyElement(A11yUI.OperationsMap.root))

        // The key, open. It says what the pin colours mean, which is half of what this frame is
        // claiming, and it is off by default because a key permanently over a map covers the map.
        app.tapWhenHittable(app.buttons[A11yUI.OperationsMap.legendToggle])
        app.expect(app.anyElement(A11yUI.OperationsMap.legend))

        // Reaching one record by searching for it, rather than by tapping a marker. A MapKit
        // marker's accessibility representation is the framework's business and changes between
        // releases; the search field is the app's own control and its result row carries the
        // app's own identifier.
        //
        // `field.typeText`, not `app.typeText`. The field sits over a live `MKMapView` whose own
        // gesture recognisers can win the tap — and when they do, the tap reports success,
        // nothing takes focus, the characters go nowhere, and the failure surfaces eight seconds
        // later as a search result that never arrived. `MapAndEditingUITests` learned that.
        let field = app.expect(app.textFields[A11yUI.OperationsMap.searchField])
        field.tap()
        field.typeText("BL-204")
        // The return key, so the keyboard is down before the card comes up. A keyboard over the
        // bottom of this screen covers the very card the frame exists to show.
        field.typeText("\n")

        app.expect(app.anyElement(A11yUI.OperationsMap.searchResult), timeout: 8).tap()
        app.expect(app.anyElement(A11yUI.OperationsMap.detailCard))

        XCTAssertEqual(
            app.keyboards.count, 0,
            """
            the keyboard is still up over the map's detail card. The capture would show it. \
            Dismiss it and re-run rather than keeping this screenshot.
            """
        )
        // Longer than the others: the camera flies to the record and the tiles under it load.
        settle(seconds: 4)
        capture(app, named: "appstore-04-operations-map")
        app.tapWhenHittable(app.buttons[A11yUI.OperationsMap.close])
    }

    private func captureTheScanReview(_ app: XCUIApplication) {
        app.tab(A11yUI.Tab.today).tap()
        // Today's scan card is the one entry point that opens the form with `startScanning` set,
        // which is what the debug hook hangs off.
        app.revealAndTap(app.buttons[A11yUI.Today.scanStart])

        let review = app.anyElement(A11yUI.Scan.reviewRoot)
        guard review.waitForExistence(timeout: 20) else {
            XCTFail(
                """
                Scan Review never opened. It is reached here by `-offrent-open-scan-review`, \
                which needs `-offrent-stub-ocr` beside it and a Debug build — the hook is inside \
                `#if DEBUG`. On screen instead:
                \(app.identifiedElements())
                """
            )
            return
        }
        // The parse runs on a task; the screen opens in `.recognising` and fills in after. A
        // photograph taken before the suggestions arrive is a picture of a spinner.
        app.expect(app.staticTexts[A11yUI.Scan.explanation], timeout: 20)
        settle()
        capture(app, named: "appstore-05-scan-review")

        app.tapWhenHittable(app.buttons[A11yUI.Scan.cancelButton])
        app.tapWhenHittable(app.buttons[A11yUI.AddRental.cancel])
    }

    // MARK: - Plumbing

    /// One screenshot of the whole screen, attached under the name the placement guide uses.
    private func capture(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        // Without this the attachment is discarded the moment the test passes, which is every
        // run that produces a usable screenshot.
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Waits for asynchronous UI — map tiles, an OCR parse, a list's first layout — to stop
    /// moving.
    ///
    /// A plain wait rather than an expectation on an element, because what is being waited for is
    /// *drawing*, and there is no element whose existence says "the map has finished rendering".
    /// The expectations above already establish that the screen is the right one; this only buys
    /// it the time to look finished.
    private func settle(seconds: TimeInterval = 2) {
        let idle = expectation(description: "the screen settles")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { idle.fulfill() }
        wait(for: [idle], timeout: seconds + 5)
    }

    /// One controlled scroll: a slow drag, not a flick.
    ///
    /// `swipeUp()` is a flick with momentum, and momentum is why the same swipe lands somewhere
    /// different on two runs of the same script. A slow drag moves the content by the distance
    /// dragged and stops there.
    private func drag(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
    }
}

extension XCUIApplication {

    /// A launch that produces the same six screenshots every time.
    ///
    /// On-disk store, wiped and reseeded — not in-memory, because the widget reads a snapshot the
    /// app writes to the App Group and an in-memory run has nothing to publish from. Clock
    /// frozen at the fixture's own instant. Pro forced on, because the widget and the map are
    /// Pro features and a capture of a paywall is not a capture of the product. Onboarding
    /// skipped, animations off, recogniser stubbed.
    static func launchedForAppStoreCapture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-offrent-reset-state",
            "-offrent-seed-appstore",
            "-offrent-fixed-now", "2026-05-09T15:00:00Z",
            "-offrent-force-pro",
            "-offrent-skip-onboarding",
            "-offrent-disable-animations",
            "-offrent-stub-ocr",
            "-offrent-open-scan-review",
        ]
        app.launch()
        return app
    }
}
