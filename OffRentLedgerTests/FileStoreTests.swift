import Testing
import UIKit
@testable import OffRentLedger

/// The evidence store. Every test writes into a fresh temporary directory, so none of them can
/// reach a real user's files.
///
/// NOT EXECUTED — no Xcode in the build environment. See TEST_MATRIX.md.
struct FileStoreTests {

    private func makeStore() -> AppFileStore {
        AppFileStore(
            containerRoot: URL.temporaryDirectory.appendingPathComponent(
                UUID().uuidString, isDirectory: true
            )
        )
    }

    private func makeImage(_ size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    @Test func writingAnImageProducesAFileAThumbnailAndADigest() async throws {
        let store = makeStore()
        let stored = try await store.writeImage(
            makeImage(CGSize(width: 3_000, height: 2_000)), ownerFolder: "item", basename: "meter"
        )
        #expect(stored.relativePath == "item/meter.jpg")
        #expect(stored.thumbnailRelativePath == "item/meter-thumb.jpg")
        #expect(stored.sha256.count == 64)
        #expect(stored.byteCount > 0)
    }

    @Test func oversizedImagesAreDownscaledBeforeStorage() async throws {
        // A 12MP frame decodes to roughly 48 MB. A hundred of them in a scrolling list is how an
        // app gets jettisoned by the OS.
        let store = makeStore()
        let stored = try await store.writeImage(
            makeImage(CGSize(width: 4_032, height: 3_024)), ownerFolder: "item", basename: "big"
        )
        let data = try #require(try? Data(contentsOf: store.url(forRelativePath: stored.relativePath)))
        let image = try #require(UIImage(data: data))
        #expect(max(image.size.width, image.size.height) <= AppConfiguration.evidenceImageMaxDimension)
    }

    @Test func reconcileNeverRemovesAReferencedFile() async throws {
        // The direction that matters. Removing something a record still points at turns a
        // tidy-up into data loss.
        let store = makeStore()
        let kept = try await store.writeImage(makeImage(CGSize(width: 100, height: 100)), ownerFolder: "a", basename: "kept")
        let orphan = try await store.writeImage(makeImage(CGSize(width: 100, height: 100)), ownerFolder: "a", basename: "orphan")

        let removed = await store.reconcile(referencedPaths: [kept.relativePath])

        #expect(removed.contains(orphan.relativePath))
        #expect(!removed.contains(kept.relativePath))
        #expect(FileManager.default.fileExists(atPath: store.url(forRelativePath: kept.relativePath).path))
    }

    @Test func reconcileKeepsTheThumbnailOfAReferencedFile() async throws {
        let store = makeStore()
        let stored = try await store.writeImage(
            makeImage(CGSize(width: 400, height: 400)), ownerFolder: "a", basename: "photo"
        )
        let removed = await store.reconcile(referencedPaths: [stored.relativePath])
        #expect(removed.isEmpty, "a thumbnail whose original is referenced is itself referenced")
    }

    @Test func pathTraversalIsRefused() async throws {
        let store = makeStore()
        let stored = try await store.writeData(
            Data("x".utf8), ownerFolder: "../../escape", filename: "../../../etc/passwd"
        )
        #expect(!stored.relativePath.contains(".."))
        let resolved = store.url(forRelativePath: stored.relativePath).standardizedFileURL.path
        #expect(resolved.hasPrefix(store.evidenceRoot.standardizedFileURL.path))
    }

    @Test func deletingAllEvidenceLeavesNothingBehind() async throws {
        let store = makeStore()
        _ = try await store.writeImage(makeImage(CGSize(width: 60, height: 60)), ownerFolder: "a", basename: "one")
        #expect(await store.totalBytesOnDisk() > 0)

        try await store.deleteAllEvidence()
        #expect(await store.totalBytesOnDisk() == 0)
        #expect(await store.existingRelativePaths().isEmpty)
    }

    @Test func theDigestIsStableForIdenticalBytes() {
        let data = Data("cedar ridge".utf8)
        #expect(AppFileStore.digest(of: data) == AppFileStore.digest(of: data))
        #expect(AppFileStore.digest(of: data) != AppFileStore.digest(of: Data("cedar ridge.".utf8)))
    }
}
