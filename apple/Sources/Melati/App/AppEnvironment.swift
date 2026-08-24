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

    /// True when running against a MELATI_TEST_DB_DIR database; sync never
    /// starts in this mode.
    private(set) var isTestMode = false

    #if DEBUG
    /// Fixed throwaway key for MELATI_TEST_DB_DIR databases so UI tests can
    /// seed the same DB from outside the app. Worthless for real data.
    static let testModeKey = Data(repeating: 0xA5, count: 32)
    #endif

    private init() {
        do {
            #if DEBUG
            // E2E seam (same pattern as scripts/migrate-from-noot.swift's
            // MIGRATE_* vars): isolated DB + fixed throwaway key. The real
            // diary DB and the keychain are never touched. The dir must be
            // inside the app's sandbox container.
            if let dir = ProcessInfo.processInfo.environment["MELATI_TEST_DB_DIR"] {
                print("!!! MELATI TEST MODE !!! isolated DB in \(dir) - sync disabled")
                isTestMode = true
                // Pref-reset seam: UI tests cannot clear the sandboxed
                // container's defaults from outside (the runner's `defaults
                // delete` is denied container writes and fails silently), so
                // the app clears its own domain. Omit the var on a relaunch
                // to exercise persistence.
                if ProcessInfo.processInfo.environment["MELATI_TEST_RESET_PREFS"] != nil {
                    UserDefaults.standard.removeObject(forKey: "melati.showPreviews")
                }
                try FileManager.default.createDirectory(
                    at: URL(fileURLWithPath: dir), withIntermediateDirectories: true)
                let url = URL(fileURLWithPath: dir).appendingPathComponent("journal.db")
                let store = try JournalStore(path: url.path, key: Self.testModeKey)
                self.store = store
                // Optional seed for manual E2E/screenshots: comma-separated
                // yyyy-MM-dd keys, seeded only if that date has no row yet.
                // Blocks init until every seed is persisted - views load from
                // the store the moment init returns, so an async seed would
                // race them (nondeterministic empty/partial first render).
                // DEBUG-only launch path; the brief block is the point.
                if let seed = ProcessInfo.processInfo.environment["MELATI_TEST_SEED"] {
                    let dates = seed
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    let seeded = DispatchSemaphore(value: 0)
                    Task.detached {
                        for date in dates where (try? await store.get(date: date)) ?? nil == nil {
                            try? await store.put(JournalEntry(
                                date: date,
                                content: "Seed entry for \(date).\nSecond line here.",
                                createdAt: Date(),
                                location: "Seedville"))
                        }
                        seeded.signal()
                    }
                    seeded.wait()
                }
                return
            }
            #endif
            let key = try KeyStore.default.loadOrCreate()
            let url = try JournalStore.defaultDatabaseURL()
            self.store = try JournalStore(path: url.path, key: key)
        } catch {
            fatalError("Melati failed to initialize encrypted storage: \(error)")
        }
    }

    /// Async on purpose - init is synchronous and fatalError-happy; sync
    /// setup must never block or kill launch. No-ops without an iCloud
    /// account (app stays fully local) or when the kill switch is off.
    func startSyncIfAvailable() {
        guard !isTestMode, SyncSettings.isEnabled, sync == nil else { return }
        Task {
            #if DEBUG
            // Repair hook: launch with `-melati.resetSyncState YES` to forget
            // all server associations (engine state, change tags) and mark
            // every entry pending - a full re-upload + re-fetch reconciled by
            // the merge logic. Local data untouched. Launch-argument values
            // live in the volatile argument domain, so this is one-shot.
            if UserDefaults.standard.bool(forKey: "melati.resetSyncState") {
                print("[melati.sync] RESET requested via launch argument - forgetting sync state")
                try? await store.resetSyncState()
            }
            #endif
            guard await CloudSyncService.accountAvailable() else {
                print("[melati.sync] no iCloud account - staying local")
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
