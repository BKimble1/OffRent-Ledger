import Foundation
import Testing
@testable import OffRentLedger

/// Copy that is a product requirement rather than a style choice, and the fixture-parity check.
///
/// NOT EXECUTED — no Xcode in the build environment.
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
}
