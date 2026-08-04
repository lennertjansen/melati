import Foundation
import Observation

@MainActor
@Observable
final class AppEnvironment {
    static let shared = AppEnvironment()

    let store: JournalStore
    var pendingEntry: JournalEntry?
    private(set) var sync: CloudSyncService?

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
            guard await CloudSyncService.accountAvailable() else {
                print("[noot.sync] no iCloud account - staying local")
                return
            }
            let service = CloudSyncService(store: store)
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
