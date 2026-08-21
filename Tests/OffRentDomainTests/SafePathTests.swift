import Foundation
import XCTest
@testable import OffRentDomain

/// Filename sanitisation.
///
/// These exist because the equivalent logic shipped broken. It neutralised `..` but let `/`
/// through, so a "filename" could still be a path several directories deep — and nothing in this
/// repository could run it without Xcode, so nothing did, until the simulator suite finally ran
/// and `FileStoreTests.pathTraversalIsRefused` caught it. Moving it into the portable layer is
/// the actual fix; these are what keep it fixed on any machine with a Swift toolchain.
final class SafePathTests: XCTestCase {

    func testTraversalReducesToASingleContainedComponent() {
        // Exactly the inputs the file store's own traversal test uses.
        let folder = SafePath.component("../../escape")
        let name = SafePath.component("../../../etc/passwd")

        XCTAssertFalse(folder.contains("/"), folder)
        XCTAssertFalse(name.contains("/"), name)
        XCTAssertFalse(folder.contains(".."), folder)
        XCTAssertFalse(name.contains(".."), name)
    }

    func testNoInputProducesAnUnusableName() {
        // The invariant the file store depends on, over every shape that has been thrown at it:
        // one component, no traversal, not hidden, never empty.
        let inputs = [
            "", ".", "..", "...", "///", "../..", "/etc/passwd", "a/../../b",
            "....//....//etc", "..\\..\\windows", "  ../  ", "photo.jpg",
            "\u{200B}", "\u{0}name", String(repeating: "../", count: 40),
        ]
        for input in inputs {
            let result = SafePath.component(input)
            XCTAssertFalse(result.isEmpty, "empty: \(input)")
            XCTAssertFalse(result.contains("/"), "separator survived: \(input) -> \(result)")
            XCTAssertFalse(result.contains(".."), "traversal survived: \(input) -> \(result)")
            XCTAssertFalse(result.hasPrefix("."), "hidden file: \(input) -> \(result)")
        }
    }

    func testOrdinaryNamesAreNotMangled() {
        // The failure a sanitiser invites is over-correction. If it rewrites the names the app
        // actually uses, every stored file is renamed and every reference to one breaks.
        for ordinary in ["photo.jpg", "photo-thumb.jpg", "CR-44821_invoice.pdf",
                         "3F2504E0-4F89-11D3-9A0C-0305E82C3301", "evidence-2026-05-09.pdf"] {
            XCTAssertEqual(SafePath.component(ordinary), ordinary)
        }
    }

    func testANameThatReducesToNothingBecomesAUUID() {
        // Exactly two inputs reduce to nothing: the empty string, and ".". Everything else
        // leaves at least one character, because a disallowed character becomes "-" rather than
        // vanishing — ".." is "-", "///" is "---", "..." is "-.". Odd-looking, but perfectly
        // good single components; the invariant that matters is the one above.
        //
        // A UUID rather than the empty string, because appending "" to a directory URL yields
        // the directory itself: the write would target the folder rather than a file in it.
        for reducesToNothing in ["", "."] {
            let result = SafePath.component(reducesToNothing)
            XCTAssertNotNil(UUID(uuidString: result), "\(reducesToNothing) -> \(result)")
        }
    }

    func testAHiddenFileIsNotProducedFromALeadingDot() {
        XCTAssertEqual(SafePath.component(".hidden"), "hidden")
        XCTAssertEqual(SafePath.component(".ssh"), "ssh")
    }
}
