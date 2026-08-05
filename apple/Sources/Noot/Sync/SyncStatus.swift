import Foundation

// User-facing sync state, kept deliberately coarse: the UI stays quiet
// (idle renders nothing) and never nags. Pure types, no CloudKit imports -
// CI-testable like the D2 logic.

enum SyncStatus: Equatable, Sendable {
    /// Kill switch off or no iCloud account: the app is fully local.
    case off
    /// Synced, nothing in flight.
    case idle
    case syncing
    case error(String)
}

/// Folds engine activity into a SyncStatus. In-flight operations are counted
/// (fetch and send can overlap); the last error sticks until a subsequent
/// success clears it, so a transient failure shows until the retry lands.
struct SyncActivity: Equatable, Sendable {
    private var inFlight = 0
    private var lastError: String?

    var status: SyncStatus {
        if inFlight > 0 { return .syncing }
        if let lastError { return .error(lastError) }
        return .idle
    }

    mutating func begin() {
        inFlight += 1
    }

    mutating func end() {
        inFlight = max(0, inFlight - 1)
    }

    mutating func noteError(_ message: String) {
        lastError = message
    }

    mutating func noteSuccess() {
        lastError = nil
    }
}

enum RemoteUpdateAction: Equatable, Sendable {
    /// Editor buffer matches what was last persisted: refresh silently.
    case refresh
    /// Buffer has unsaved edits: never stomp them. Autosave wins LWW by
    /// design (the losing revision is preserved in conflict_backups on the
    /// device it came from); show a passive notice instead.
    case notice
}

enum RemoteUpdatePolicy {
    static func action(
        bufferContent: String,
        bufferLocation: String?,
        persistedContent: String,
        persistedLocation: String?
    ) -> RemoteUpdateAction {
        let clean = bufferContent == persistedContent
            && (bufferLocation ?? "") == (persistedLocation ?? "")
        return clean ? .refresh : .notice
    }
}
