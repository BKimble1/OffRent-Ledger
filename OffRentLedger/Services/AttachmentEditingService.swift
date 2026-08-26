import Foundation
import SwiftData

/// Renaming, captioning and removing an attachment.
///
/// A service rather than three methods on a view, for the reason the previous version failed:
/// the caption was written straight into the model from a `TextField` binding with no save at
/// all, and nothing anywhere could tell whether it had persisted. Logic that decides what the
/// store holds belongs somewhere a test can call it.
///
/// It does not touch the file system. Removing a record and removing the bytes are different
/// operations with different failure modes, so this returns the paths and the caller deletes
/// them once the record is safely gone — never before, or a failed save leaves a rental claiming
/// a photograph it cannot produce.
struct AttachmentEditingService {

    let context: ModelContext

    /// The name a reader of the evidence packet sees. Never blank.
    static func sanitisedName(_ proposed: String, fallingBackTo current: String) -> String {
        let trimmed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? current : trimmed
    }

    /// - Returns: a sentence to show the user, or nil when the change is on disk.
    @discardableResult
    func rename(
        _ asset: EvidenceAsset,
        to proposedName: String,
        caption proposedCaption: String?
    ) -> String? {
        let previousName = asset.displayName
        let previousCaption = asset.caption

        asset.displayName = Self.sanitisedName(proposedName, fallingBackTo: previousName)
        asset.caption = proposedCaption?.nilIfBlank

        if let failure = PersistentStore.save(context, describing: "This attachment") {
            // Put it back, so the screen and the store cannot disagree about what the caption
            // says. `rollback` alone is not enough: these are edits to a live model object and
            // the in-memory values would otherwise stand.
            asset.displayName = previousName
            asset.caption = previousCaption
            context.rollback()
            return failure
        }
        return nil
    }

    /// Removes the record and reports which files the caller should now delete.
    ///
    /// - Returns: a failure sentence, or the paths whose bytes are now unreferenced.
    func remove(_ asset: EvidenceAsset) -> Result<[String], String> {
        // Read before deleting: reading a property off a deleted model is not something to rely
        // on, and these paths are the only way to find the bytes afterwards.
        let paths = [asset.relativePath, asset.thumbnailRelativePath].compactMap { $0 }
        context.delete(asset)

        if let failure = PersistentStore.save(context, describing: "That removal") {
            context.rollback()
            return .failure(failure)
        }
        return .success(paths)
    }
}
