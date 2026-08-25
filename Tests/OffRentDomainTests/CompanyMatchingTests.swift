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

    // MARK: - Matching a scanned letterhead

    private func company(_ name: String, branch: String? = nil) -> CompanyIdentity {
        CompanyIdentity(id: UUID(), name: name, branch: branch)
    }

    func testALetterheadFindsTheYardTheUserAlreadySaved() throws {
        // The failure this replaces: the scan yields the full legal letterhead and the saved
        // record is what the user typed, so a `contains` in either direction is false and the
        // contractor is invited to create a second copy of a yard they already have.
        let saved = [company("Cedar Ridge Equipment"), company("Foundry Tool Supply")]
        let match = try XCTUnwrap(
            CompanyMatching.bestMatch(forScannedName: "CEDAR RIDGE EQUIPMENT RENTAL LLC", in: saved)
        )
        XCTAssertEqual(match.identity.name, "Cedar Ridge Equipment")
        XCTAssertEqual(match.score, 1.0, accuracy: 0.0001)
    }

    func testLegalSuffixesAndNoiseWordsDoNotCountAgainstAMatch() {
        let saved = [company("Ridgeline Equipment Co")]
        XCTAssertNotNil(
            CompanyMatching.bestMatch(forScannedName: "RIDGELINE EQUIPMENT, INC.", in: saved),
            "a suffix is not an identity"
        )
    }

    func testAnUnrelatedLetterheadMatchesNothing() {
        let saved = [company("Cedar Ridge Equipment"), company("Foundry Tool Supply")]
        XCTAssertNil(
            CompanyMatching.bestMatch(forScannedName: "PIEDMONT CIVIL LLC", in: saved),
            "the contractor's own company is not one of their rental yards"
        )
    }

    func testTwoEquallyGoodCandidatesReturnNothingRatherThanAGuess() {
        // Two branches of one firm, saved separately on purpose. Picking one would put the wrong
        // phone number on the rental, which is the thing `duplicate(ofName:)` exists to prevent.
        let saved = [
            company("Cedar Ridge Equipment", branch: "Marlin Falls"),
            company("Cedar Ridge Equipment", branch: "Plano"),
        ]
        XCTAssertNil(
            CompanyMatching.bestMatch(forScannedName: "CEDAR RIDGE EQUIPMENT", in: saved),
            "an ambiguous match is the user's decision, not the app's"
        )
    }

    func testAWeakOverlapIsNotAMatch() {
        // A saved name with four informative words, of which the scan shares one.
        let saved = [company("Cedar Ridge Equipment and Tool Hire of Texas")]
        XCTAssertNil(
            CompanyMatching.bestMatch(forScannedName: "CEDAR SPRINGS DRILLING", in: saved)
        )
    }

    func testMatchingIsNotConfusedByPunctuationOrCase() throws {
        let saved = [company("O'Malley Plant & Tool")]
        let match = try XCTUnwrap(
            CompanyMatching.bestMatch(forScannedName: "o'malley plant and tool, llc", in: saved)
        )
        XCTAssertEqual(match.identity.name, "O'Malley Plant & Tool")
    }
}
