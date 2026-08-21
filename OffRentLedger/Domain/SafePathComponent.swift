import Foundation

/// Turning untrusted text into a filename.
///
/// This lives in `Domain` rather than beside the file store on purpose. It is pure string
/// handling with no filesystem in it, it is the boundary an attacker-controlled name crosses,
/// and the portable suite is the only place in this project where it can be executed on any
/// machine. It used to live in `AppFileStore` — where nothing could run it without Xcode — and a
/// separator-shaped hole in it went unnoticed until the simulator suite finally ran.
enum SafePath {

    /// Reduces a value to a single, safe path **component**.
    ///
    /// The result is one component, never a path: `/` is not in the allowed set, and that is the
    /// entire point. The earlier version did allow it, so `component("../../../etc/passwd")`
    /// returned `-/-/-/etc/passwd` — the `..` were neutralised but the separators survived, and
    /// the "filename" was still three directories deep. It could not climb above the evidence
    /// root, but it did land a write in folders nobody had created, so the write threw rather
    /// than being contained.
    ///
    /// Order matters. Separators become `-` *first*, so a `..` split across one is collapsed by
    /// the pass that follows rather than surviving it: `a/../../b` reduces to `a-----b`, not to
    /// something still carrying a `..`.
    ///
    /// A name that reduces to nothing gets a UUID. Returning an empty string would append
    /// nothing to the directory URL, so the "file" would be the directory.
    static func component(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        // An explicit loop, not `map { ... ? Character($0) : "-" }.reduce(into: "")`. In the
        // chained form the type checker has to decide that the `"-"` literal is a `Character`
        // from the other arm of a ternary, inside a closure whose result type it is also
        // solving for — the kind of expression it can spend an unbounded amount of time on.
        var cleaned = ""
        for scalar in value.unicodeScalars {
            if allowed.contains(scalar) {
                cleaned.append(Character(scalar))
            } else {
                cleaned.append("-")
            }
        }
        while cleaned.contains("..") { cleaned = cleaned.replacingOccurrences(of: "..", with: "-") }
        // A leading dot would make a hidden file, and on its own is `.` — a name meaning "this
        // directory" rather than a file in it.
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        return cleaned.isEmpty ? UUID().uuidString : cleaned
    }
}
