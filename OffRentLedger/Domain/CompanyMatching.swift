import Foundation

/// A rental company as far as duplicate detection is concerned.
struct CompanyIdentity: Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var branch: String?

    init(id: UUID, name: String, branch: String? = nil) {
        self.id = id
        self.name = name
        self.branch = branch
    }
}

/// Whether a company the user is about to create already exists.
///
/// The rule the product wants is narrow on purpose: catch the accident — the same yard typed
/// twice because the user did not scroll far enough to see it in the list — and never refuse a
/// company that is genuinely different. "Cedar Ridge Equipment" in Marlin Falls and "Cedar Ridge
/// Equipment" in Plano are two branches a contractor deals with separately, and merging them
/// would put the wrong phone number on a rental.
///
/// So: normalise, compare name *and* branch, and require an exact match on both.
enum CompanyMatching {

    /// Lowercased, punctuation removed, whitespace collapsed.
    ///
    /// Legal suffixes are deliberately *not* stripped. "Ridgeline Equipment" and "Ridgeline
    /// Equipment LLC" may well be the same company, but they may also be a yard and its parent,
    /// and this rule is not permitted to guess: it only prevents typing the same thing twice.
    static func normalised(_ text: String) -> String {
        let lowered = text.lowercased()
        var kept = ""
        var lastWasSpace = true
        for character in lowered {
            if character.isLetter || character.isNumber {
                kept.append(character)
                lastWasSpace = false
            } else if !lastWasSpace {
                kept.append(" ")
                lastWasSpace = true
            }
        }
        return kept.trimmingCharacters(in: .whitespaces)
    }

    /// The comparison key. A missing branch and a blank branch are the same thing.
    static func key(name: String, branch: String?) -> String {
        let branchKey = normalised(branch ?? "")
        return branchKey.isEmpty ? normalised(name) : "\(normalised(name))|\(branchKey)"
    }

    /// The existing company this one would duplicate, if any.
    ///
    /// Returns the record rather than a bool so the caller can offer "use the one you already
    /// have" instead of only refusing.
    static func duplicate(
        ofName name: String,
        branch: String?,
        in existing: [CompanyIdentity],
        excluding excludedID: UUID? = nil
    ) -> CompanyIdentity? {
        let candidateKey = key(name: name, branch: branch)
        guard !candidateKey.isEmpty else { return nil }
        return existing.first { record in
            guard record.id != excludedID else { return false }
            return key(name: record.name, branch: record.branch) == candidateKey
        }
    }

    /// Whether a name is enough to save. The one required field on the company form.
    static func isUsableName(_ name: String) -> Bool {
        !normalised(name).isEmpty
    }
}

/// Whether an email address is plausible enough to store.
///
/// Deliberately permissive: the field is optional, the value is only ever handed to the user's
/// own mail app, and a validator strict enough to reject a real address is worse than one that
/// accepts a typo. It rejects the shapes that could not possibly work at all.
enum EmailValidation {
    static func isPlausible(_ candidate: String) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true } // blank is fine; the field is optional
        guard !trimmed.contains(" ") else { return false }
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let host = parts[1]
        guard host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".") else { return false }
        return true
    }
}
