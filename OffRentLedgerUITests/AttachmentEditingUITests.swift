import Foundation
import XCTest

/// The attachment editor, driven the way a user reaches it.
///
/// The unit suite covers what the store ends up holding — `AttachmentEditingTests` renames,
/// captions, removes and refetches. None of that says the screen is reachable, that Save is
/// wired to it, or that the destructive path asks first. This does.
///
/// The fixture files a record with no bytes behind it, because XCUITest cannot take a
/// photograph. Renaming, captioning and removing never read the file, so they behave here
/// exactly as they do against a real one — and the preview, which does read it, gets to prove it
/// says so rather than opening onto an empty sheet.
final class AttachmentEditingUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    /// Rentals › the fixture rental › attachments › the one attachment on it.
    ///
    /// Returns once the name field is up rather than once the screen's own identifier resolves:
    /// the field is the thing every test here needs next, and waiting on a container whose
    /// element *type* is SwiftUI's choice is how this suite has lost afternoons before.
    private func openTheAttachment() -> XCUIApplication {
        // The photo picker stands aside for this suite. It is an out-of-process service that
        // keeps the app from going idle, and while it is on screen XCUITest cannot snapshot the
        // hierarchy at all — every query times out, including ones about rows that are there.
        // Nothing about the editor under test needs it.
        let app = XCUIApplication.launched(seed: .attachment, stubbingThePhotoPicker: true)
        app.tab(A11yUI.Tab.rentals).tap()
        app.openRental(named: "Skid Steer Loader")
        app.revealAndTap(app.anyElement(A11yUI.ItemDetail.manageAttachments))
        app.revealAndTap(app.expect(app.anyElement(A11yUI.Attachment.openRow)))
        app.expect(app.textFields[A11yUI.Attachment.name])
        return app
    }

    /// Clears a field by deleting what is in it, character by character.
    ///
    /// Not press-and-hold plus "Select All": that depends on the edit menu appearing, on its
    /// wording, and on the press not being read as a drag. Deletes depend on none of those.
    private func replace(_ field: XCUIElement, in app: XCUIApplication, with text: String) {
        let existing = (field.value as? String) ?? ""
        field.tap()
        if !existing.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        app.typeText(text)
    }

    func testTheNameAndCaptionSurviveLeavingAndComingBack() {
        let app = openTheAttachment()

        replace(app.textFields[A11yUI.Attachment.name], in: app, with: "Boom cylinder, delivery day")

        // The caption is `TextField(axis: .vertical)`, which SwiftUI may realise as either a text
        // field or a text view depending on the platform and how many lines it is showing — so it
        // is looked up by identifier across any type rather than by a guess at which one.
        app.revealAndTap(app.anyElement(A11yUI.Attachment.caption))
        app.typeText("Hairline crack visible on the left ram.")
        app.dismissKeyboard()

        app.tapWhenHittable(app.expect(app.buttons[A11yUI.Attachment.save]))

        // Back on the attachments list, then into the editor a second time. Reading the field
        // back on the same screen would only prove the `@State` still holds what was typed,
        // which was equally true of the version that never saved at all.
        app.revealAndTap(app.expect(app.anyElement(A11yUI.Attachment.openRow)))
        let reopened = app.expect(app.textFields[A11yUI.Attachment.name])
        XCTAssertEqual(
            reopened.value as? String, "Boom cylinder, delivery day",
            "the name has to come back from the store, not from the field that typed it"
        )
        XCTAssertEqual(
            app.anyElement(A11yUI.Attachment.caption).value as? String,
            "Hairline crack visible on the left ram.",
            "the caption is the half that used to be written into the model and never saved"
        )
    }

    func testABlankNameCannotBeSaved() {
        let app = openTheAttachment()

        replace(app.textFields[A11yUI.Attachment.name], in: app, with: "")
        app.dismissKeyboard()

        let save = app.expect(app.buttons[A11yUI.Attachment.save])
        XCTAssertFalse(
            save.isEnabled,
            "a blank name against a photograph in an evidence packet is worse than a generated one"
        )
        XCTAssertTrue(
            app.expect(app.staticTexts[A11yUI.Attachment.missingRequirement]).exists,
            "and the screen has to say why the button is off"
        )
    }

    func testRemovingAsksFirstAndThenTheAttachmentIsGone() {
        let app = openTheAttachment()

        app.revealAndTap(app.expect(app.buttons[A11yUI.Attachment.delete]))
        // The confirmation is the point. This deletes the photograph from the phone as well as
        // the record, and it used to be an invisible swipe with nothing asking.
        app.expect(app.buttons[A11yUI.Attachment.confirmDelete].firstMatch).tap()

        XCTAssertFalse(
            app.anyElement(A11yUI.Attachment.openRow).waitForExistence(timeout: 5),
            "the row must be gone from the list the editor returned to"
        )
    }

    func testAPreviewWithNoFileBehindItSaysSoRatherThanOpeningOntoNothing() {
        let app = openTheAttachment()

        app.revealAndTap(app.expect(app.buttons[A11yUI.Attachment.preview]))

        // The fixture deliberately has no bytes. Before this, the sheet presented before the read
        // finished and simply stayed empty when the read failed — a preview onto nothing, with no
        // way to tell a missing file from a broken app.
        XCTAssertTrue(
            app.staticTexts["This file could not be opened"].waitForExistence(timeout: 10),
            "a preview that cannot find its file has to say which of the two is missing"
        )
    }
}
