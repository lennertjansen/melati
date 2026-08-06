import CloudKit

// Edge-state decisions as pure functions, seam-tested like the D2 logic.
// The service executes these plans; nothing here touches the engine or store.

enum AccountEvent: Equatable, Sendable {
    case signIn, signOut, switchAccounts
}

struct AccountChangePlan: Equatable, Sendable {
    /// Forget every server association (system_fields, engine state), mark
    /// all entries pending. The journal itself is NEVER purged.
    let resetSyncState: Bool
    /// Rebuild the engine and fetch: local entries upload, the account's
    /// records download, LWW merges. Off after sign-out - a fresh engine
    /// still runs (it is how the later sign-in event reaches us) but there
    /// is nothing to merge into.
    let restartEngine: Bool
    /// Status to publish when the plan leaves the engine idle.
    let statusWhenDone: SyncStatus?
}

enum UploadFailureAction: Equatable, Sendable {
    /// serverRecordChanged: run the LWW conflict path.
    case resolveConflict
    /// Zone vanished under us: recreate it and re-add the record.
    case recreateZone
    /// Out of iCloud space: keep pending, surface distinct status. Clears
    /// itself when a later upload succeeds.
    case quotaFull
    /// Expected transient (offline, throttled): the engine retries with its
    /// own backoff; the UI stays quiet - offline writing is a normal state.
    case retryQuietly
    /// Unexpected failure: keep pending but surface the error line.
    case retryShowError
}

enum SyncEdgePolicy {
    static func plan(for event: AccountEvent) -> AccountChangePlan {
        switch event {
        case .signIn:
            return AccountChangePlan(resetSyncState: true, restartEngine: true, statusWhenDone: nil)
        case .signOut:
            return AccountChangePlan(resetSyncState: true, restartEngine: true, statusWhenDone: .off)
        case .switchAccounts:
            // The previous account's change tags must not leak into the new
            // account's zone: full reset, then merge.
            return AccountChangePlan(resetSyncState: true, restartEngine: true, statusWhenDone: nil)
        }
    }

    static func uploadFailureAction(for code: CKError.Code) -> UploadFailureAction {
        switch code {
        case .serverRecordChanged:
            return .resolveConflict
        case .zoneNotFound, .userDeletedZone:
            return .recreateZone
        case .quotaExceeded:
            return .quotaFull
        case .networkUnavailable, .networkFailure, .serviceUnavailable,
             .requestRateLimited, .zoneBusy, .accountTemporarilyUnavailable,
             .notAuthenticated:
            return .retryQuietly
        default:
            return .retryShowError
        }
    }

    /// Same quiet set for fetch failures: being offline must not show an
    /// error line every time the app foregrounds without a connection.
    static func fetchFailureIsQuiet(_ code: CKError.Code) -> Bool {
        switch code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable,
             .requestRateLimited, .zoneBusy, .accountTemporarilyUnavailable,
             .notAuthenticated:
            return true
        default:
            return false
        }
    }
}
