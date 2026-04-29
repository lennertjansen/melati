import Foundation

struct JournalEntry: Sendable, Equatable {
    let date: String
    let content: String
    let createdAt: Date?
    let location: String?
}

struct EntrySummary: Sendable, Equatable {
    let date: String
    let preview: String
    let createdAt: Date?
}
