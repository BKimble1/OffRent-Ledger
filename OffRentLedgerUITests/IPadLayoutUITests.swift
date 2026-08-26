import Foundation
import XCTest

/// The app on an iPad: the whole window, all four orientations, and a column of content narrow
/// enough to read rather than a row whose label and value are a thousand points apart.
///
/// These run on an iPad simulator only — `verify.yml`'s `ipad` job names this class — and the
/// first thing every test does is prove the window really is iPad-sized. There is deliberately
/// no `XCTSkip` here. A destination that quietly resolved to an iPhone would leave the job green
/// having proved nothing about iPad, and this suite has already been caught once by tests that
/// compiled, were counted, and never ran.
///
/// The width check is also the only test in the repository that can see
/// `TARGETED_DEVICE_FAMILY`. An iPhone-only binary launched on an iPad runs letterboxed in
/// compatibility mode, and XCUITest reports the app's frame as the scaled iPhone frame — well
/// under 700 points. So `requireIPad` fails the moment somebody drops the `,2`.
final class IPadLayoutUITests: XCTestCase {

    /// The widest a column of content is allowed to get. Mirrors `Layout.readableWidth`; the two
    /// are kept in step by `verify_repository.py` rather than shared, because the UI test target
    /// does not link the app's design system.
    private static let readableWidth: CGFloat = 700

    /// The narrowest iPad is the mini at 744 points across in portrait. The widest iPhone is the
    /// Pro Max at 440. Anything above 700 is an iPad showing a universal app.
    private static let narrowestIPad: CGFloat = 700

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        // A left-over landscape orientation is inherited by whatever runs next, and a test that
        // silently changes the device for its neighbours is worse than one that fails.
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: - Tests

    /// The app gets the whole iPad window, and its content sits in a centred, capped column.
    func testTheAppFillsTheIPadWindowAndKeepsAReadableColumn() {
        let app = XCUIApplication.launched()
        requireIPad(app)

        app.tab(A11yUI.Tab.today).tap()
        app.expect(app.anyElement(A11yUI.Today.root))

        assertReadableColumn(app.expect(app.anyElement(A11yUI.Today.scanCard)), in: app,
                             describing: "the scan card on Today")
    }

    /// A `List` is capped too. Inset-grouped rows stretch the full window by default, and a row
    /// 1300 points wide puts its label and its value at opposite ends of the desk.
    func testASettingsListKeepsAReadableColumn() {
        let app = XCUIApplication.launched()
        requireIPad(app)

        app.tab(A11yUI.Tab.settings).tap()
        app.expect(app.anyElement(A11yUI.Settings.root))

        assertReadableColumn(app.expect(app.anyElement(A11yUI.Settings.subscription)), in: app,
                             describing: "the subscription row in Settings")
    }

    /// Landscape, which an iPad app must support — there is no `UIRequiresFullScreen` in the
    /// Info.plist, so iPadOS will only offer Split View if the app follows the window round.
    func testTheAppWorksInLandscapeAndComesBack() {
        let app = XCUIApplication.launched()
        requireIPad(app)

        app.tab(A11yUI.Tab.today).tap()
        let portraitWidth = app.frame.width

        XCUIDevice.shared.orientation = .landscapeLeft
        app.expect(app.anyElement(A11yUI.Today.root))
        XCTAssertGreaterThan(
            app.frame.width, portraitWidth,
            "the window did not get wider, so the app never rotated into landscape"
        )
        // The wide case is the whole point of the cap: this is where an unconstrained screen
        // would be stretched to thirteen hundred points.
        assertReadableColumn(app.expect(app.anyElement(A11yUI.Today.scanCard)), in: app,
                             describing: "the scan card on Today in landscape")

        // The tabs still work rotated. A tab bar that moved out from under the app's own
        // identifiers would take every other test on this device with it.
        app.tab(A11yUI.Tab.rentals).tap()
        app.expect(app.anyElement(A11yUI.Rentals.root))

        XCUIDevice.shared.orientation = .portrait
        app.expect(app.anyElement(A11yUI.Rentals.root))
        XCTAssertEqual(
            app.frame.width, portraitWidth, accuracy: 1,
            "the window did not return to its portrait size"
        )
    }

    /// The save bar on the longest form in the app, on an iPad, in landscape, with the keyboard
    /// up — the arrangement that leaves the least room between the two.
    func testTheSaveBarStaysReachableOnIPadInLandscape() {
        let app = XCUIApplication.launched(seed: .empty)
        requireIPad(app)

        XCUIDevice.shared.orientation = .landscapeLeft

        app.tab(A11yUI.Tab.rentals).tap()
        app.openNewRental()

        app.expect(app.textFields[A11yUI.AddRental.equipmentName]).tap()
        app.typeText("Mini Excavator")

        let save = app.expect(app.buttons[A11yUI.AddRental.save])
        XCTAssertTrue(save.exists)
        if app.keyboards.count > 0 {
            XCTAssertLessThan(
                save.frame.maxY, app.keyboards.element.frame.minY,
                "the save bar is behind the keyboard"
            )
        }

        app.dismissKeyboard()
        XCTAssertLessThanOrEqual(
            save.frame.maxY, app.frame.maxY,
            "the save bar runs off the bottom of the screen"
        )
        XCTAssertLessThanOrEqual(
            save.frame.width, Self.readableWidth,
            "the save button is stretched the full width of the iPad instead of sitting in the "
            + "same column as the form it belongs to"
        )
    }

    // MARK: - Helpers

    /// Fails unless the app really has an iPad-sized window.
    private func requireIPad(
        _ app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThan(
            app.frame.width, Self.narrowestIPad,
            """
            this class must run on an iPad simulator, and the app's window is only \
            \(app.frame.width) points wide. Either the destination is an iPhone, or the app is \
            running letterboxed in iPhone compatibility mode because TARGETED_DEVICE_FAMILY no \
            longer includes 2.
            """,
            file: file, line: line
        )
    }

    /// Fails unless an element sits inside the readable column, centred in the window.
    private func assertReadableColumn(
        _ element: XCUIElement,
        in app: XCUIApplication,
        describing what: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let box = element.frame
        XCTAssertLessThanOrEqual(
            box.width, Self.readableWidth,
            "\(what) is \(box.width) points wide, past the \(Self.readableWidth)-point cap",
            file: file, line: line
        )
        XCTAssertEqual(
            box.midX, app.frame.midX, accuracy: 2,
            "\(what) is not centred in the window",
            file: file, line: line
        )
    }
}
