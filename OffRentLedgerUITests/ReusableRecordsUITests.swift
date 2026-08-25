import Foundation
import XCTest

/// §12.1–3: companies and jobsites are records, not fields on a form.
///
/// The screenshots showed the shape this replaces: a New Rental screen with company name, branch,
/// phone and email inlined into it, and a plus button on Rentals that could only make a rental.
/// So the same yard got typed in again every time, and there was no way to add one before the
/// first machine.
final class ReusableRecordsUITests: XCTestCase {

    override func setUp() { continueAfterFailure = false }

    /// §12.1: the plus offers all three.
    func testThePlusMenuOffersRentalCompanyAndJobsite() {
        let app = XCUIApplication.launched(seed: .empty)

        app.tab(A11yUI.Tab.rentals).tap()
        app.tapWhenHittable(app.expect(app.buttons[A11yUI.Rentals.addMenu]))

        // By title as well as by identifier: a SwiftUI `Menu` becomes a `UIMenu`, and an
        // identifier set on the `Button` does not reliably survive that translation.
        for (identifier, title) in [
            (A11yUI.Rentals.addRental, "New rental"),
            (A11yUI.Rentals.addCompany, "New rental company"),
            (A11yUI.Rentals.addJobSite, "New jobsite"),
        ] {
            XCTAssertTrue(
                app.expect(app.menuItem(identifier, titled: title), timeout: 5).exists,
                "the plus menu does not offer \(title)"
            )
        }
    }

    /// §12.2: a company made from the Rentals tab is reusable in New Rental.
    func testACompanyCreatedFromRentalsIsSelectableInANewRental() {
        let app = XCUIApplication.launched(seed: .empty)

        app.tab(A11yUI.Tab.rentals).tap()
        app.openNewCompanyFromMenu()

        app.expect(app.textFields[A11yUI.Company.name]).tap()
        app.typeText("Foundry Tool Supply")
        app.expect(app.textFields[A11yUI.Company.branch]).tap()
        app.typeText("West Yard")
        app.dismissKeyboard()
        app.tapWhenHittable(app.expect(app.buttons[A11yUI.Company.save]))

        // Back on Rentals, and immediately visible under Rental companies.
        app.tapInContent(app.expect(app.buttons[A11yUI.Rentals.companiesLink]))
        XCTAssertTrue(
            app.staticTexts["Foundry Tool Supply"].waitForExistence(timeout: 5),
            "a company saved from the Rentals tab must appear in the list straight away"
        )
        app.back()

        // And it is there to pick, without being typed again.
        app.openNewRental()
        app.tapInContent(app.expect(app.anyElement(A11yUI.AddRental.companyRow)))
        XCTAssertTrue(
            app.expect(app.anyElement(A11yUI.Company.pickerRoot)).exists,
            "the company row must open a picker, not an inline form"
        )
        XCTAssertTrue(
            app.staticTexts["Foundry Tool Supply"].waitForExistence(timeout: 5),
            "the company created a moment ago is not offered"
        )
    }

    /// §12.3: creating a company from inside a draft returns to it, selected, with the draft
    /// intact. The failure this guards is the worst one in the flow — losing a half-filled form.
    func testACompanyCreatedInsideADraftComesBackSelected() {
        let app = XCUIApplication.launched(seed: .empty)

        app.tab(A11yUI.Tab.rentals).tap()
        app.openNewRental()

        app.expect(app.textFields[A11yUI.AddRental.equipmentName]).tap()
        app.typeText("Telehandler 10K")
        app.dismissKeyboard()

        app.addCompanyFromDraft(named: "Cedar Ridge Equipment")

        XCTAssertTrue(
            app.anyElement(A11yUI.AddRental.root).waitForExistence(timeout: 8),
            "saving the company must return to the rental draft"
        )
        XCTAssertEqual(
            app.textFields[A11yUI.AddRental.equipmentName].value as? String, "Telehandler 10K",
            "the draft was discarded while a company was being created"
        )
        XCTAssertTrue(
            app.staticTexts["Cedar Ridge Equipment"].waitForExistence(timeout: 5),
            "the new company must be selected on the row that created it"
        )
    }

    /// A disabled Save always says what is missing, by name.
    func testSaveNamesTheMissingRequirement() {
        let app = XCUIApplication.launched(seed: .empty)

        app.tab(A11yUI.Tab.rentals).tap()
        app.openNewRental()

        let save = app.expect(app.buttons[A11yUI.AddRental.save])
        XCTAssertFalse(save.isEnabled, "an empty draft must not be saveable")

        let missing = app.expect(app.staticTexts[A11yUI.AddRental.missingRequirement])
        XCTAssertTrue(
            missing.label.contains("equipment name") && missing.label.contains("rental company"),
            "a disabled Save must name both missing requirements, not merely be grey: \\(missing.label)"
        )

        app.expect(app.textFields[A11yUI.AddRental.equipmentName]).tap()
        app.typeText("Mini Excavator")
        app.dismissKeyboard()

        XCTAssertTrue(
            app.expect(app.staticTexts[A11yUI.AddRental.missingRequirement]).label
                .contains("rental company"),
            "the message must narrow to what is still missing"
        )
    }

    /// A jobsite is optional, and saying so is a first-class choice rather than an empty picker.
    func testAJobsiteIsOptionalAndTheEditorIsTheMapOne() {
        let app = XCUIApplication.launched(seed: .empty)

        app.tab(A11yUI.Tab.rentals).tap()
        app.openNewRental()
        app.tapInContent(app.expect(app.anyElement(A11yUI.AddRental.jobSiteRow)))

        app.expect(app.anyElement(A11yUI.Jobsite.pickerRoot))
        XCTAssertTrue(
            app.buttons[A11yUI.Jobsite.none].exists,
            "a rental that never leaves the yard must be able to have no jobsite"
        )

        // Add New opens the map editor, not a text field.
        app.tapWhenHittable(app.expect(app.buttons[A11yUI.Jobsite.addNew]))
        app.expect(app.anyElement(A11yUI.Jobsite.root))
        XCTAssertTrue(
            app.anyElement(A11yUI.Jobsite.map).waitForExistence(timeout: 8),
            "the jobsite editor must be a map, not a search box"
        )
        XCTAssertTrue(app.textFields[A11yUI.Jobsite.searchField].exists)

        // Cancelling returns to the draft with nothing created.
        app.tapWhenHittable(app.expect(app.buttons[A11yUI.Jobsite.cancel]))
        XCTAssertTrue(app.anyElement(A11yUI.Jobsite.pickerRoot).waitForExistence(timeout: 5))
    }
}
