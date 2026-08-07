import Foundation

struct JournalEntry: Sendable, Equatable {
    let date: String
    let content: String
    let createdAt: Date?
    let location: String?
    /// Set by the store on read; ignored by put(), which stamps its own.
    let modifiedAt: Date?

    init(date: String, content: String, createdAt: Date?, location: String?, modifiedAt: Date? = nil) {
        self.date = date
        self.content = content
        self.createdAt = createdAt
        self.location = location
        self.modifiedAt = modifiedAt
    }
}

struct EntrySummary: Sendable, Equatable, Identifiable {
    let date: String
    let preview: String
    let createdAt: Date?
    let location: String?

    var id: String { date }
}
