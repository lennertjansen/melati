import Foundation
import Observation

@MainActor
@Observable
final class AppEnvironment {
    static let shared = AppEnvironment()

    let store: JournalStore
    var pendingEntry: JournalEntry?
    private(set) var sync: CloudSyncService?
    /// Quiet UI surface: .off until sync starts (kill switch / no account).
    private(set) var syncStatus: SyncStatus = .off

    private init() {
        do {
            let key = try KeyStore.default.loadOrCreate()
            let url = try JournalStore.defaultDatabaseURL()
            self.store = try JournalStore(path: url.path, key: key)
        } catch {
            fatalError("Noot failed to initialize encrypted storage: \(error)")
        }
    }

    /// Async on purpose - init is synchronous and fatalError-happy; sync
    /// setup must never block or kill launch. No-ops without an iCloud
    /// account (app stays fully local) or when the kill switch is off.
    func startSyncIfAvailable() {
        guard SyncSettings.isEnabled, sync == nil else { return }
        Task {
            #if DEBUG
            // Repair hook: launch with `-noot.resetSyncState YES` to forget
            // all server associations (engine state, change tags) and mark
            // every entry pending - a full re-upload + re-fetch reconciled by
            // the merge logic. Local data untouched. Launch-argument values
            // live in the volatile argument domain, so this is one-shot.
            if UserDefaults.standard.bool(forKey: "noot.resetSyncState") {
                print("[noot.sync] RESET requested via launch argument - forgetting sync state")
                try? await store.resetSyncState()
            }
            #endif
            guard await CloudSyncService.accountAvailable() else {
                print("[noot.sync] no iCloud account - staying local")
                return
            }
            let service = CloudSyncService(store: store) { [weak self] status in
                self?.syncStatus = status
            }
            sync = service
            await service.start()
            await service.fetchNow()
        }
    }

    /// Foreground fetch backstop; safe to call any time.
    func syncFetchNow() {
        guard let sync else { return }
        Task { await sync.fetchNow() }
    }

    func flushPending() async {
        guard let entry = pendingEntry else { return }
        do {
            try await store.put(entry)
        } catch {
            print("flushPending failed: \(error)")
        }
        pendingEntry = nil
    }
}
