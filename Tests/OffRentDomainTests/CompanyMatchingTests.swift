import Foundation
import XCTest
@testable import OffRentDomain

/// Catching the accident without refusing the legitimate case.
final class CompanyMatchingTests: XCTestCase {

    private let cedarMarlin = CompanyIdentity(
        id: UUID(), name: "Cedar Ridge Equipment Rental LLC", branch: "Marlin Falls"
    )
    private let cedarPlano = CompanyIdentity(
        id: UUID(), name: "Cedar Ridge Equipment Rental LLC", branch: "Plano"
    )
    private let noBranch = CompanyIdentity(id: UUID(), name: "Foundry Tool Supply")

    private var existing: [CompanyIdentity] { [cedarMarlin, cedarPlano, noBranch] }

    // MARK: - Normalising

    func testCaseAndPunctuationAndSpacingAreIgnored() {
        XCTAssertEqual(
            CompanyMatching.normalised("Cedar Ridge Equipment Rental, LLC."),
            CompanyMatching.normalised("cedar ridge  equipment rental llc")
        )
    }

    func testNormalisingLeavesNoLeadingOrTrailingSpace() {
        XCTAssertEqual(CompanyMatching.normalised("  Cedar Ridge!  "), "cedar ridge")
    }

    func testAnEntirelyPunctuationalNameNormalisesToNothing() {
        XCTAssertEqual(CompanyMatching.normalised("---"), "")
        XCTAssertFalse(CompanyMatching.isUsableName("---"))
        XCTAssertFalse(CompanyMatching.isUsableName("   "))
        XCTAssertTrue(CompanyMatching.isUsableName("A1"))
    }

    // MARK: - Duplicates

    func testTypingTheSameCompanyTwiceIsCaught() {
        let found = CompanyMatching.duplicate(
            ofName: "cedar ridge equipment rental, llc",
            branch: "MARLIN FALLS",
            in: existing
        )
        XCTAssertEqual(found?.id, cedarMarlin.id)
    }

    func testADifferentBranchOfTheSameCompanyIsNotADuplicate() {
        // The case the rule must never refuse: two yards of one chain, with different phone
        // numbers, that a contractor deals with separately.
        XCTAssertNil(
            CompanyMatching.duplicate(
                ofName: "Cedar Ridge Equipment Rental LLC", branch: "Odessa", in: existing
            )
        )
    }

    func testASuffixDifferenceIsNotAssumedToBeTheSameCompany() {
        // "Ridgeline Equipment" and "Ridgeline Equipment LLC" may be a yard and its parent. The
        // rule is not permitted to guess.
        let candidates = [CompanyIdentity(id: UUID(), name: "Ridgeline Equipment LLC")]
        XCTAssertNil(
            CompanyMatching.duplicate(ofName: "Ridgeline Equipment", branch: nil, in: candidates)
        )
    }

    func testABlankBranchAndNoBranchAreTheSameThing() {
        XCTAssertEqual(
            CompanyMatching.duplicate(ofName: "Foundry Tool Supply", branch: "   ", in: existing)?.id,
            noBranch.id
        )
        XCTAssertEqual(
            CompanyMatching.duplicate(ofName: "Foundry Tool Supply", branch: nil, in: existing)?.id,
            noBranch.id
        )
    }

    func testAddingABranchToACompanyThatHadNoneIsNotADuplicate() {
        XCTAssertNil(
            CompanyMatching.duplicate(ofName: "Foundry Tool Supply", branch: "West", in: existing)
        )
    }

    func testEditingARecordDoesNotFindItself() {
        XCTAssertNil(
            CompanyMatching.duplicate(
                ofName: cedarMarlin.name,
                branch: cedarMarlin.branch,
                in: existing,
                excluding: cedarMarlin.id
            )
        )
    }

    func testABlankNameMatchesNothingRatherThanEverything() {
        let blanks = [CompanyIdentity(id: UUID(), name: "  ")]
        XCTAssertNil(CompanyMatching.duplicate(ofName: "   ", branch: nil, in: blanks))
    }
}

/// Permissive on purpose: the field is optional and the value only ever reaches the user's own
/// mail app. A validator strict enough to reject a real address is worse than one that lets a
/// typo through.
final class EmailValidationTests: XCTestCase {

    func testOrdinaryAddressesAreAccepted() {
        for address in [
            "yard@cedarridge.com", "a.b+tag@sub.domain.co.uk", "SALES@CEDARRIDGE.COM",
        ] {
            XCTAssertTrue(EmailValidation.isPlausible(address), address)
        }
    }

    func testBlankIsAcceptedBecauseTheFieldIsOptional() {
        XCTAssertTrue(EmailValidation.isPlausible(""))
        XCTAssertTrue(EmailValidation.isPlausible("   "))
    }

    func testShapesThatCouldNotPossiblyWorkAreRejected() {
        for address in ["yard", "yard@", "@cedarridge.com", "yard@cedar ridge.com",
                        "yard@cedarridge", "yard@.com", "yard@com.", "a@b@c.com"] {
            XCTAssertFalse(EmailValidation.isPlausible(address), address)
        }
    }
}
