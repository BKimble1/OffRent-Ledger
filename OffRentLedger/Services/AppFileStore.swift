import CryptoKit
import Foundation
import OSLog
import UIKit

/// Where documents and photographs live.
protocol FileStoring: Sendable {
    /// Root the relative paths in `EvidenceAsset` are resolved against.
    var evidenceRoot: URL { get }

    func url(forRelativePath path: String) -> URL
    /// Takes encoded image `Data` rather than a `UIImage`: the store is an actor and `UIImage`
    /// is not `Sendable`, so a bitmap cannot cross into it. Decoding happens inside.
    func writeImage(_ imageData: Data, ownerFolder: String, basename: String) async throws -> StoredFile
    func writeData(_ data: Data, ownerFolder: String, filename: String) async throws -> StoredFile
    func delete(relativePath: String) async
    /// Removes any file under the evidence root that no record refers to.
    @discardableResult
    func reconcile(referencedPaths: Set<String>) async -> [String]
    func deleteAllEvidence() async throws
    func totalBytesOnDisk() async -> Int64
    func existingRelativePaths() async -> Set<String>
}

struct StoredFile: Sendable, Equatable {
    var relativePath: String
    var thumbnailRelativePath: String?
    var byteCount: Int
    var sha256: String
}

enum FileStoreError: Error, Equatable {
    case couldNotCreateDirectory(String)
    case couldNotEncodeImage
    case writeFailed(String)
    /// The requested path escaped the evidence root. Always a bug, never a user's doing, but
    /// worth refusing rather than following.
    case pathEscapesRoot(String)
}

/// The evidence store, as an actor.
///
/// It is an actor because scanning a multi-page PDF writes several files while the user is
/// already scrolling the review sheet, and because thumbnail generation must not land on the main
/// thread. Everything here is off the main actor by construction rather than by remembering to
/// dispatch.
actor AppFileStore: FileStoring {

    private static let logger = Logger(subsystem: "com.idlery.offrent", category: "files")

    nonisolated let evidenceRoot: URL
    private let fileManager = FileManager.default

    /// - Parameter containerRoot: Application Support in production; a temporary directory in
    ///   tests, which is why no test ever touches a real user's evidence.
    init(containerRoot: URL) {
        self.evidenceRoot = containerRoot.appendingPathComponent("OffRentLedger/Evidence", isDirectory: true)
    }

    static func applicationSupport() -> AppFileStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return AppFileStore(containerRoot: base)
    }

    nonisolated func url(forRelativePath path: String) -> URL {
        evidenceRoot.appendingPathComponent(path)
    }

    // MARK: - Writing

    func writeImage(
        _ imageData: Data, ownerFolder: String, basename: String
    ) async throws -> StoredFile {
        guard let image = UIImage(data: imageData) else {
            throw FileStoreError.couldNotEncodeImage
        }
        // Downscaled before encoding. A 12MP camera frame is ~4 MB of JPEG and decodes to ~48 MB
        // in memory; a hundred of them in a scrolling list is how an app gets jettisoned.
        let scaled = image.downscaled(toMaxDimension: AppConfiguration.evidenceImageMaxDimension)
        guard let data = scaled.jpegData(
            compressionQuality: AppConfiguration.evidenceImageCompressionQuality
        ) else {
            throw FileStoreError.couldNotEncodeImage
        }

        var stored = try writeDataSynchronously(data, ownerFolder: ownerFolder, filename: "\(basename).jpg")

        if let thumbnail = scaled.downscaled(toMaxDimension: AppConfiguration.thumbnailMaxDimension)
            .jpegData(compressionQuality: 0.7) {
            let thumb = try? writeDataSynchronously(
                thumbnail, ownerFolder: ownerFolder, filename: "\(basename)-thumb.jpg"
            )
            stored.thumbnailRelativePath = thumb?.relativePath
        }
        return stored
    }

    func writeData(_ data: Data, ownerFolder: String, filename: String) async throws -> StoredFile {
        try writeDataSynchronously(data, ownerFolder: ownerFolder, filename: filename)
    }

    private func writeDataSynchronously(
        _ data: Data, ownerFolder: String, filename: String
    ) throws -> StoredFile {
        let safeFolder = Self.sanitise(ownerFolder)
        let safeName = Self.sanitise(filename)
        let directory = evidenceRoot.appendingPathComponent(safeFolder, isDirectory: true)

        guard directory.standardizedFileURL.path.hasPrefix(evidenceRoot.standardizedFileURL.path) else {
            throw FileStoreError.pathEscapesRoot(ownerFolder)
        }

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw FileStoreError.couldNotCreateDirectory(directory.lastPathComponent)
        }

        let destination = directory.appendingPathComponent(safeName)
        do {
            // `completeUntilFirstUserAuthentication` rather than `complete`: the widget's snapshot
            // refresh and any future background work run before the user unlocks, and files that
            // cannot be read then would fail silently rather than visibly.
            try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Self.logger.error("Evidence write failed: \(String(describing: error), privacy: .private)")
            throw FileStoreError.writeFailed(safeName)
        }

        return StoredFile(
            relativePath: "\(safeFolder)/\(safeName)",
            thumbnailRelativePath: nil,
            byteCount: data.count,
            sha256: Self.digest(of: data)
        )
    }

    // MARK: - Deleting

    func delete(relativePath: String) async {
        let target = url(forRelativePath: relativePath).standardizedFileURL
        guard target.path.hasPrefix(evidenceRoot.standardizedFileURL.path) else { return }
        try? fileManager.removeItem(at: target)
    }

    /// Deletes files under the evidence root that nothing refers to, and returns what it removed.
    ///
    /// The direction of this is the safety property, and it is the one the test covers: a file
    /// **in** `referencedPaths` is never touched, whatever else is true. A sweep that deletes
    /// something a record still points at turns a tidy-up into data loss.
    @discardableResult
    func reconcile(referencedPaths: Set<String>) async -> [String] {
        guard let enumerator = fileManager.enumerator(
            at: evidenceRoot, includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [] }

        var removed: [String] = []
        let rootPath = evidenceRoot.standardizedFileURL.path

        // `while let ... = enumerator.nextObject()` rather than `for case let ... in`:
        // `NSEnumerator.makeIterator()` is unavailable from an asynchronous context (it is
        // an error in the Swift 6 language mode), because a `for-in` over it would block the
        // cooperative thread inside the iterator. `nextObject()` is the supported form.
        while let entry = enumerator.nextObject() {
            guard let fileURL = entry as? URL else { continue }
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }

            let path = fileURL.standardizedFileURL.path
            guard path.hasPrefix(rootPath) else { continue }
            var relative = String(path.dropFirst(rootPath.count))
            if relative.hasPrefix("/") { relative.removeFirst() }

            // Thumbnails are referenced through their parent asset's record; a thumbnail whose
            // original is still referenced is itself referenced.
            let isReferencedThumbnail = relative.hasSuffix("-thumb.jpg")
                && referencedPaths.contains(relative.replacingOccurrences(of: "-thumb.jpg", with: ".jpg"))

            guard !referencedPaths.contains(relative), !isReferencedThumbnail else { continue }
            try? fileManager.removeItem(at: fileURL)
            removed.append(relative)
        }

        if !removed.isEmpty {
            Self.logger.info("Reconciled \(removed.count, privacy: .public) unreferenced evidence files")
        }
        return removed
    }

    func deleteAllEvidence() async throws {
        guard fileManager.fileExists(atPath: evidenceRoot.path) else { return }
        try fileManager.removeItem(at: evidenceRoot)
    }

    // MARK: - Inspecting

    func existingRelativePaths() async -> Set<String> {
        guard let enumerator = fileManager.enumerator(
            at: evidenceRoot, includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [] }
        let rootPath = evidenceRoot.standardizedFileURL.path
        var paths: Set<String> = []
        // `while let ... = enumerator.nextObject()` rather than `for case let ... in`:
        // `NSEnumerator.makeIterator()` is unavailable from an asynchronous context (it is
        // an error in the Swift 6 language mode), because a `for-in` over it would block the
        // cooperative thread inside the iterator. `nextObject()` is the supported form.
        while let entry = enumerator.nextObject() {
            guard let fileURL = entry as? URL else { continue }
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            else { continue }
            var relative = String(fileURL.standardizedFileURL.path.dropFirst(rootPath.count))
            if relative.hasPrefix("/") { relative.removeFirst() }
            paths.insert(relative)
        }
        return paths
    }

    func totalBytesOnDisk() async -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: evidenceRoot, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        // `while let ... = enumerator.nextObject()` rather than `for case let ... in`:
        // `NSEnumerator.makeIterator()` is unavailable from an asynchronous context (it is
        // an error in the Swift 6 language mode), because a `for-in` over it would block the
        // cooperative thread inside the iterator. `nextObject()` is the supported form.
        while let entry = enumerator.nextObject() {
            guard let fileURL = entry as? URL else { continue }
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
        return total
    }

    // MARK: - Helpers

    /// SHA-256, lowercase hex.
    ///
    /// An integrity aid, and nothing more. It lets a user tell whether the attachment in an export
    /// is the attachment that was captured. It is not tamper-evidence, not notarisation and not a
    /// chain of custody, and the UI says so wherever it appears.
    nonisolated static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Keeps a filename to a safe alphabet and prevents traversal.
    nonisolated static func sanitise(_ component: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./"))
        // An explicit loop, not `map { ... ? Character($0) : "-" }.reduce(into: "")`. In the
        // chained form the type checker has to decide that the `"-"` literal is a `Character`
        // from the other arm of a ternary, inside a closure whose result type it is also
        // solving for — the kind of expression it can spend an unbounded amount of time on.
        var cleaned = ""
        for scalar in component.unicodeScalars {
            if allowed.contains(scalar) {
                cleaned.append(Character(scalar))
            } else {
                cleaned.append("-")
            }
        }
        while cleaned.contains("..") { cleaned = cleaned.replacingOccurrences(of: "..", with: "-") }
        while cleaned.hasPrefix("/") { cleaned.removeFirst() }
        return cleaned.isEmpty ? UUID().uuidString : cleaned
    }
}

extension UIImage {
    /// Aspect-preserving downscale. Returns self when already small enough, so a screenshot-sized
    /// image is not needlessly re-encoded.
    func downscaled(toMaxDimension maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return self }
        let scale = maxDimension / longest
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
