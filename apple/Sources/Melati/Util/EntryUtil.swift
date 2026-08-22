import Foundation

enum EntryUtil {
    struct MonthGroup: Equatable {
        let month: String
        let entries: [EntrySummary]
    }

    /// Buckets summaries by their "yyyy-MM" prefix, preserving input order.
    /// The store returns summaries date-DESC, so groups (and the entries
    /// inside each) come out newest-first without re-sorting.
    static func monthGroups(_ summaries: [EntrySummary]) -> [MonthGroup] {
        var ordered: [String] = []
        var byMonth: [String: [EntrySummary]] = [:]
        for s in summaries {
            let mk = String(s.date.prefix(7))
            if byMonth[mk] == nil {
                ordered.append(mk)
                byMonth[mk] = []
            }
            byMonth[mk]?.append(s)
        }
        return ordered.map { MonthGroup(month: $0, entries: byMonth[$0] ?? []) }
    }

    static func extractPreview(from content: String, maxLength: Int = 100) -> String {
        let lines = content.split(whereSeparator: \.isNewline).map(String.init)
        for line in lines {
            let cleaned = stripMarkdown(line)
            guard !cleaned.isEmpty else { continue }
            // Skip lines that are pure punctuation/symbols (e.g. lone "\", "---").
            guard cleaned.contains(where: { $0.isLetter || $0.isNumber }) else { continue }
            if cleaned.count <= maxLength { return cleaned }
            let endIndex = cleaned.index(cleaned.startIndex, offsetBy: maxLength)
            return String(cleaned[..<endIndex]).trimmingCharacters(in: .whitespaces) + "…"
        }
        return ""
    }

    private static func stripMarkdown(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*[-*+]\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*>\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"__([^_]+)__"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\*([^*]+)\*"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"_([^_]+)_"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\\"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
