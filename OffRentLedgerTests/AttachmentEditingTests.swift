import Foundation
import SwiftData
import XCTest

@testable import OffRentLedger

/// Editing and removing an attachment.
///
/// The behaviour these cover did technically exist before and did not work. The caption was
/// written into the model from a `TextField` binding with no save anywhere, so whether it reached
/// the store was up to SwiftData's autosave and nothing on screen said either way; and the only
/// way to remove anything was an invisible swipe. Both are worth pinning at the level that
/// decides what the store holds, rather than at the level that decides what a screen looks like.
@MainActor
final class AttachmentEditingTests: XCTestCase {

    private var context: ModelContext!

    override func setUpWithError() throws {
        context = ModelContext(try ModelContainerFactory.make(inMemory: true))
    }

    override func tearDown() {
        context = nil
    }

    // MARK: - Renaming and captioning

    func testRenamingAndCaptioningSurvivesARefetch() throws {
        let asset = makeAsset()
        context.insert(asset)
        XCTAssertNil(PersistentStore.save(context, describing: "setup"))

        let service = AttachmentEditingService(context: context)
        XCTAssertNil(service.rename(asset, to: "Cracked bucket pin", caption: "Left side, day 6"))

        // Refetched rather than read back off the same object: an assignment that never reached
        // the store still reads correctly from the instance that made it, which is exactly how
        // the old version looked like it worked.
        let stored = try XCTUnwrap(fetchOnlyAsset())
        XCTAssertEqual(stored.displayName, "Cracked bucket pin")
        XCTAssertEqual(stored.caption, "Left side, day 6")
    }

    func testAnEmptyCaptionIsStoredAsNothingRatherThanAnEmptyString() throws {
        let asset = makeAsset(caption: "Something")
        context.insert(asset)
        XCTAssertNil(PersistentStore.save(context, describing: "setup"))

        let service = AttachmentEditingService(context: context)
        XCTAssertNil(service.rename(asset, to: asset.displayName, caption: "   "))

        let stored = try XCTUnwrap(fetchOnlyAsset())
        XCTAssertNil(
            stored.caption,
            "whitespace is not a caption, and an empty string in the evidence packet draws an "
                + "empty line under the photograph"
        )
    }

    /// A blank name keeps the one it had.
    ///
    /// The name is the only thing identifying a photograph to whoever reads the evidence packet.
    /// A generated name nobody chose beats no name at all, so this cannot be cleared — the screen
    /// disables Save as well, and this is the half that holds if anything ever calls the service
    /// directly.
    func testABlankNameFallsBackToTheExistingOne() throws {
        let asset = makeAsset(displayName: "Scan 3")
        context.insert(asset)
        XCTAssertNil(PersistentStore.save(context, describing: "setup"))

        let service = AttachmentEditingService(context: context)
        XCTAssertNil(service.rename(asset, to: "    ", caption: nil))

        let stored = try XCTUnwrap(fetchOnlyAsset())
        XCTAssertEqual(stored.displayName, "Scan 3")
    }

    // MARK: - Removing

    func testRemovingTakesTheRecordAndNamesTheFilesToDelete() throws {
        let asset = makeAsset()
        asset.thumbnailRelativePath = "thumbs/one.jpg"
        context.insert(asset)
        XCTAssertNil(PersistentStore.save(context, describing: "setup"))

        let service = AttachmentEditingService(context: context)
        switch service.remove(asset) {
        case let .failed(message):
            XCTFail("removing should have succeeded: \(message)")
        case let .removed(paths):
            // Both the file and its thumbnail. Leaving the thumbnail behind is a photograph the
            // user believes they deleted, still on the phone.
            XCTAssertEqual(Set(paths), ["evidence/one.jpg", "thumbs/one.jpg"])
        }

        XCTAssertNil(try fetchOnlyAsset(), "the record is still in the store after removal")
    }

    func testRemovingReportsEveryPathEvenWithoutAThumbnail() throws {
        let asset = makeAsset()
        asset.thumbnailRelativePath = nil
        context.insert(asset)
        XCTAssertNil(PersistentStore.save(context, describing: "setup"))

        switch AttachmentEditingService(context: context).remove(asset) {
        case let .failed(message):
            XCTFail("removing should have succeeded: \(message)")
        case let .removed(paths):
            XCTAssertEqual(paths, ["evidence/one.jpg"])
        }
    }

    // MARK: - Fixture

    private func makeAsset(
        displayName: String = "Photo 1",
        caption: String? = nil
    ) -> EvidenceAsset {
        EvidenceAsset(
            relativePath: "evidence/one.jpg",
            mediaType: .image,
            displayName: displayName,
            capturedAt: Date(timeIntervalSince1970: 1_777_000_000),
            caption: caption
        )
    }

    private func fetchOnlyAsset() throws -> EvidenceAsset? {
        try context.fetch(FetchDescriptor<EvidenceAsset>()).first
    }
}
