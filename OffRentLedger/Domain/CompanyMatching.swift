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

    /// Words that carry no identity, so they are ignored when matching a scanned letterhead.
    ///
    /// Only for `bestMatch(forScannedName:in:)`. `normalised` deliberately keeps them, because
    /// telling a user their new company duplicates an existing one is a refusal and must be
    /// exact. Suggesting which saved yard a scan probably names is the opposite: a guess the
    /// user confirms with one look.
    private static let uninformativeWords: Set<String> = [
        "inc", "llc", "l l c", "co", "corp", "corporation", "company", "ltd", "limited",
        "lp", "llp", "the", "and", "of", "group", "holdings", "usa", "us",
    ]

    /// The saved company a scanned letterhead most likely names, and how sure that is.
    ///
    /// Not `contains`. The obvious implementation compares the two strings for containment and
    /// gets it backwards: the scan yields the full legal letterhead — `CEDAR RIDGE EQUIPMENT
    /// RENTAL LLC` — and the saved record is what the user typed, `Cedar Ridge Equipment`. Asking
    /// whether the long string is inside the short one is always false, so a yard the contractor
    /// already had was reported as new and they created a second copy of it. Which is the
    /// duplicate-company problem this whole area exists to prevent, arriving through the door
    /// marked "convenience".
    ///
    /// Token overlap instead, scored as the share of the *saved* name's informative words that
    /// the scan also contains. That direction is deliberate: a saved "Cedar Ridge Equipment"
    /// scores 1.0 against a longer letterhead naming it, while a saved "Cedar Ridge Equipment
    /// and Tool Hire of Texas" scores lower against a letterhead that only says "Cedar Ridge" —
    /// which is right, because that is a weaker claim.
    ///
    /// Returns `nil` rather than a bad guess when nothing scores at least `0.6`, or when two
    /// candidates tie: an ambiguous match is the user's decision, not the app's.
    static func bestMatch(
        forScannedName scanned: String, in existing: [CompanyIdentity]
    ) -> (identity: CompanyIdentity, score: Double)? {
        let scannedWords = informativeWords(scanned)
        guard !scannedWords.isEmpty else { return nil }

        var scored: [(identity: CompanyIdentity, score: Double)] = []
        for candidate in existing {
            let candidateWords = informativeWords(candidate.name)
            guard !candidateWords.isEmpty else { continue }
            let shared = candidateWords.intersection(scannedWords).count
            let score = Double(shared) / Double(candidateWords.count)
            if score >= 0.6 { scored.append((candidate, score)) }
        }
        guard let best = scored.max(by: { $0.score < $1.score }) else { return nil }
        // A tie is an ambiguity, and this returns a suggestion the user is meant to accept at a
        // glance. Two yards that both look right is precisely when not to guess.
        let tied = scored.filter { abs($0.score - best.score) < 0.0001 }
        guard tied.count == 1 else { return nil }
        return best
    }

    private static func informativeWords(_ text: String) -> Set<String> {
        Set(
            normalised(text)
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count > 1 && !uninformativeWords.contains($0) }
        )
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
