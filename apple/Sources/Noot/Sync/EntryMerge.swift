import Foundation

// Chronological append-merge for forked entries. The rule that makes it
// safe: content the other side has never seen is NEVER discarded - it is
// stacked, older above newer, so the day reads top-to-bottom. The rule that
// makes it converge: the output is deterministic for a given pair of
// versions, so two devices merging the same fork produce identical content.

enum EntryMerge {
    /// Trimmed verbatim containment. An empty needle is contained in
    /// anything - an empty side never forces a merge.
    static func contains(_ haystack: String, _ needle: String) -> Bool {
        let n = needle.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { return true }
        return haystack.contains(n)
    }

    /// Stack two divergent versions: older above, newer below, one blank
    /// line between. Callers decide which is which (see merge).
    static func stack(older: String, newer: String) -> String {
        let top = trimEdges(older)
        let bottom = trimEdges(newer)
        if top.isEmpty { return bottom }
        if bottom.isEmpty { return top }
        return top + "\n\n" + bottom
    }

    /// Order two forked versions by stamp (older first) and stack them.
    /// Equal stamps order by content so both devices still agree.
    static func merge(aContent: String, aStamp: String, bContent: String, bStamp: String) -> String {
        switch SyncReconciler.compare(aStamp, bStamp) {
        case .orderedAscending:
            return stack(older: aContent, newer: bContent)
        case .orderedDescending:
            return stack(older: bContent, newer: aContent)
        case .orderedSame:
            return aContent <= bContent
                ? stack(older: aContent, newer: bContent)
                : stack(older: bContent, newer: aContent)
        }
    }

    /// Strip blank edges only - leading newlines and trailing whitespace.
    /// Interior formatting (and leading indentation of the first line, which
    /// can be markdown-significant) is untouched.
    private static func trimEdges(_ s: String) -> String {
        var out = Substring(s)
        while let f = out.first, f.isNewline { out = out.dropFirst() }
        while let l = out.last, l.isNewline || l == " " || l == "\t" { out = out.dropLast() }
        return String(out)
    }
}
