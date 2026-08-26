import Foundation
import Testing
@testable import OffRentLedger

/// Copy that is a product requirement rather than a style choice, and the fixture-parity check.
///
/// Executed on the simulator by the `offrent-fast-verify` workflow.
struct CopyTests {

    @Test func theDisclosureSaysBothRequiredThings() {
        let disclosure = AppCopy.offRentDisclosure
        #expect(disclosure.contains("does not notify the rental company"))
        #expect(disclosure.contains("Contact the vendor directly"))
        #expect(disclosure.contains("confirmation number"))
    }

    @Test func theAffirmationIsAboutWhatTheUserDidNotWhatTheAppDid() {
        #expect(AppCopy.confirmationAffirmation.hasPrefix("I contacted"))
        #expect(AppCopy.confirmationAffirmationHint.contains("has no way to check"))
    }

    @Test func noRequiredCopyMakesABannedClaim() {
        let all = [
            AppCopy.offRentDisclosure, AppCopy.offRentDisclosureShort, AppCopy.markDoneExplanation,
            AppCopy.confirmationAffirmation, AppCopy.confirmationAffirmationHint,
            AppCopy.estimateExplanation, AppCopy.possibleMismatchExplanation,
            AppCopy.scanReviewExplanation, AppCopy.ocrLocalOnly, AppCopy.checksumExplanation,
            AppCopy.localOnlySummary, AppCopy.locationExplanation, AppCopy.notificationsExplanation,
            AppCopy.entitlementLossReassurance, AppCopy.subscriptionTerms, AppCopy.generalDisclaimer,
        ].joined(separator: " ").lowercased()

        for banned in [
            "guaranteed", "verified overcharge", "legal proof", "tamper-proof",
            "vendor notified", "rental ended", "we contacted",
        ] {
            #expect(!all.contains(banned), "banned phrase in required copy: \(banned)")
        }
    }

    @Test func theEntitlementReassuranceNamesWhatSurvives() {
        let text = AppCopy.entitlementLossReassurance.lowercased()
        for word in ["edit", "resolve", "export", "delete"] {
            #expect(text.contains(word))
        }
    }

    @Test func subscriptionTermsCoverApplesRequiredDisclosures() {
        let terms = AppCopy.subscriptionTerms.lowercased()
        #expect(terms.contains("apple account"))
        #expect(terms.contains("renews automatically"))
        #expect(terms.contains("24 hours"))
        #expect(terms.contains("cancel"))
    }
}

/// The UI test suite scans a stub whose text must match the committed fixture; otherwise a UI
/// test asserting "$285.00" passes against text that no parser test ever saw.
struct FixtureParityTests {

    @Test func theStubContractMatchesTheCommittedFixture() throws {
        let url = try #require(
            Bundle.main.url(forResource: "contract_skidsteer_clean", withExtension: "txt")
        )
        let fixture = try String(contentsOf: url, encoding: .utf8)
        let stub = StubTextRecognizer.skidSteerContract

        for line in ["RENTAL AGREEMENT NO: CR-44821", "UNIT #: SS-2214", "DAILY RATE: $285.00"] {
            #expect(fixture.contains(line), "fixture drifted: \(line)")
            #expect(stub.document.rawText.contains(line), "stub drifted: \(line)")
        }
    }

    /// The same parity rule for the contract the App Store capture scans.
    ///
    /// And one more thing besides: the values on that page have to be the machine the *other*
    /// five screenshots are of. A gallery whose scan frame quotes a different yard and a
    /// different day rate from its dashboard frame is six pictures of two products.
    @Test func theAppStoreStubMatchesItsFixtureAndTheCaptureData() throws {
        let url = try #require(
            Bundle.main.url(forResource: "contract_appstore_excavator", withExtension: "txt")
        )
        let fixture = try String(contentsOf: url, encoding: .utf8)
        let stub = StubTextRecognizer.appStoreExcavatorContract

        for line in [
            "SUMMIT RENTAL CO.",
            "RENTAL AGREEMENT NO: SR-58204",
            "UNIT #: EX-118",
            "SERIAL NUMBER: 5KX2290741",
            "DATE OUT: 05/05/2026",
            "DAILY RATE: $425.00",
        ] {
            #expect(fixture.contains(line), "fixture drifted: \(line)")
            #expect(stub.document.rawText.contains(line), "stub drifted: \(line)")
        }

        // The company, case-insensitively. A letterhead prints SUMMIT RENTAL CO. and the record
        // it has to agree with is "Summit Rental Co." — the same rental company, shouted. The
        // skid-steer fixture does the same thing with CEDAR RIDGE EQUIPMENT RENTAL LLC, because
        // that is what a recogniser reads off the top of a contract. The assertion is about
        // which yard the scan names, not about which of the two was in caps.
        //
        // Everything below it is an identifier, and identifiers are compared exactly: EX-118 is
        // not the same unit as ex-118, and a fixture that disagreed with the record about the
        // case of a unit number would be a real disagreement.
        let machine = AppStoreCaptureFixture.miniExcavator
        #expect(
            stub.document.rawText.range(
                of: machine.company.name, options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil,
            "the scanned contract names a different rental company from the fixture's"
        )
        #expect(fixture.contains(machine.vendorEquipmentIdentifier))
        #expect(fixture.contains(machine.serialNumber))
        #expect(fixture.contains(machine.agreementNumber))
        #expect(fixture.contains(machine.purchaseOrderNumber))
    }
}
