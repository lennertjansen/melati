import CloudKit
import Foundation

// The CloudKit adapter: connects the store's sync API (D1) to the pure LWW
// logic (D2) through CKSyncEngine. This file owns all engine interaction;
// nothing else in the app imports CloudKit except JournalRecordCoder.

extension Notification.Name {
    /// Posted on the main actor after remote changes land locally.
    /// userInfo["dates"] is a Set<String> of affected dateKeys.
    static let nootEntriesChangedRemotely = Notification.Name("NootEntriesChangedRemotely")
}

enum SyncSettings {
    static let enabledKey = "noot.sync.enabled"

    /// Kill switch: `defaults write com.lennertjansen.noot noot.sync.enabled -bool NO`
    /// (or the same key in iOS UserDefaults). Defaults to on - sync is core.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }
}

actor CloudSyncService {
    /// Keeps CloudKit imports out of AppEnvironment.
    static func accountAvailable() async -> Bool {
        let status = try? await CKContainer(identifier: "iCloud.com.lennertjansen.noot").accountStatus()
        return status == .available
    }

    private let store: JournalStore
    private var engine: CKSyncEngine?
    private var changesTask: Task<Void, Never>?

    private static let engineStateKey = "engine_state"
    private static let zoneCreatedKey = "zone_created"

    init(store: JournalStore) {
        self.store = store
    }

    // MARK: - Lifecycle

    func start() async {
        guard engine == nil else { return }

        var serialization: CKSyncEngine.State.Serialization?
        if let data = try? await store.syncMeta(key: Self.engineStateKey) {
            serialization = try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
        }

        let container = CKContainer(identifier: "iCloud.com.lennertjansen.noot")
        let configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: serialization,
            delegate: self
        )
        let engine = CKSyncEngine(configuration)
        self.engine = engine

        // First run: create the zone before anything can upload into it.
        if (try? await store.syncMeta(key: Self.zoneCreatedKey)) == nil {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncSchema.zoneID))])
        }

        // Launch reconcile: re-add anything unacknowledged. Heals a crash
        // between a DB commit and the engine-state save; idempotent because
        // uploads are upserts.
        if let pending = try? await store.pendingDates(), !pending.isEmpty {
            engine.state.add(pendingRecordZoneChanges: pending.map { .saveRecord(SyncSchema.recordID(dateKey: $0)) })
        }

        // Every local write becomes a pending upload.
        changesTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.store.localChanges
            for await change in stream {
                await self.noteLocalChange(change)
            }
        }
        log("sync engine started")
    }

    func stop() {
        changesTask?.cancel()
        changesTask = nil
        engine = nil
        log("sync engine stopped")
    }

    /// Foreground backstop: push is best-effort (absent on mac dev builds),
    /// the engine's own scheduler covers the rest.
    func fetchNow() async {
        guard let engine else { return }
        do {
            try await engine.fetchChanges()
        } catch {
            log("fetchChanges failed: \(error)")
        }
    }

    private func noteLocalChange(_ change: LocalChange) {
        guard let engine else { return }
        switch change {
        case .entryChanged(let date):
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(SyncSchema.recordID(dateKey: date))])
        }
    }

    private func log(_ message: String) {
        print("[noot.sync] \(message)")
    }
}

// MARK: - CKSyncEngineDelegate

extension CloudSyncService: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let stateUpdate):
            if let data = try? JSONEncoder().encode(stateUpdate.stateSerialization) {
                try? await store.setSyncMeta(key: Self.engineStateKey, value: data)
            }

        case .fetchedRecordZoneChanges(let changes):
            await applyFetchedChanges(changes)

        case .sentRecordZoneChanges(let sent):
            await handleSentChanges(sent)

        case .sentDatabaseChanges:
            try? await store.setSyncMeta(key: Self.zoneCreatedKey, value: Data([1]))

        case .accountChange(let change):
            // D5 hardens this (reset + merge on switch). For now: log loudly.
            log("account change: \(change.changeType)")

        case .fetchedDatabaseChanges(let changes):
            for deletion in changes.deletions where deletion.zoneID == SyncSchema.zoneID {
                // Zone deleted from another device/dashboard. D5 re-uploads;
                // for now log - local data is untouched by design.
                log("zone deleted remotely - local data kept, sync paused until reset")
            }

        case .willFetchChanges, .didFetchChanges, .willSendChanges, .didSendChanges,
             .willFetchRecordZoneChanges, .didFetchRecordZoneChanges:
            break

        @unknown default:
            log("unhandled event: \(event)")
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pending.isEmpty else { return nil }

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            let date = recordID.recordName
            guard let entry = try? await self.store.get(date: date) else {
                // Entry vanished locally (shouldn't happen - we never delete);
                // drop the pending change rather than uploading garbage.
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                return nil
            }
            let syncRow = try? await self.store.syncRow(date: date)
            let record = Self.record(fromSystemFields: syncRow?.systemFields ?? nil)
                ?? CKRecord(recordType: SyncSchema.recordType, recordID: recordID)
            JournalRecordCoder.encode(
                date: date,
                content: entry.content,
                createdAt: entry.createdAt.map(Self.iso.string(from:)),
                location: entry.location,
                modifiedAt: entry.modifiedAt.map(Self.iso.string(from:)) ?? Self.iso.string(from: Date()),
                onto: record
            )
            return record
        }
    }

    // MARK: - Fetched changes -> local

    private func applyFetchedChanges(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) async {
        var touched = Set<String>()

        for modification in changes.modifications {
            guard let remote = JournalRecordCoder.decode(modification.record) else { continue }
            let systemFields = Self.systemFieldsData(of: modification.record)
            let local = try? await store.get(date: remote.date)
            let localModifiedAt = local?.modifiedAt.map(Self.iso.string(from:))
            let contentEqual = local?.content == remote.content && local?.location == remote.location

            let resolution = SyncReconciler.resolveFetch(
                localModifiedAt: localModifiedAt,
                localContentEqualsRemote: contentEqual,
                remote: remote
            )
            switch resolution {
            case .applyRemote:
                let hadLocal = local != nil
                try? await store.putFromSync(
                    date: remote.date,
                    content: remote.content,
                    createdAt: remote.createdAt,
                    location: remote.location,
                    modifiedAt: remote.modifiedAt,
                    systemFields: systemFields,
                    backupReason: hadLocal ? "lww-remote-won" : nil
                )
                touched.insert(remote.date)
            case .keepLocalStoreTag:
                try? await store.storeSystemFields(date: remote.date, systemFields)
            case .identical:
                try? await store.markUploaded(date: remote.date, uploadedModifiedAt: remote.modifiedAt, systemFields: systemFields)
            }
        }

        for deletion in changes.deletions {
            let date = deletion.recordID.recordName
            try? await store.deleteFromSync(date: date)
            touched.insert(date)
        }

        if !touched.isEmpty {
            let dates = touched
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .nootEntriesChangedRemotely,
                    object: nil,
                    userInfo: ["dates": dates]
                )
            }
        }
    }

    // MARK: - Sent changes <- server verdicts

    private func handleSentChanges(_ sent: CKSyncEngine.Event.SentRecordZoneChanges) async {
        for saved in sent.savedRecords {
            guard let remote = JournalRecordCoder.decode(saved) else { continue }
            try? await store.markUploaded(
                date: saved.recordID.recordName,
                uploadedModifiedAt: remote.modifiedAt,
                systemFields: Self.systemFieldsData(of: saved)
            )
        }

        for failure in sent.failedRecordSaves {
            let date = failure.record.recordID.recordName
            guard let ckError = failure.error as? CKError else {
                log("save failed (\(date)): \(failure.error)")
                continue
            }
            switch ckError.code {
            case .serverRecordChanged:
                await resolveUploadConflict(date: date, serverRecord: ckError.serverRecord)
            case .zoneNotFound, .userDeletedZone:
                engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncSchema.zoneID))])
                engine?.state.add(pendingRecordZoneChanges: [.saveRecord(failure.record.recordID)])
            default:
                // Quota, network, throttling: keep pending; the engine retries
                // with its own backoff. D5 surfaces status to the UI.
                log("save failed (\(date)): \(ckError.code) - will retry")
            }
        }
    }

    private func resolveUploadConflict(date: String, serverRecord: CKRecord?) async {
        guard let serverRecord, let server = JournalRecordCoder.decode(serverRecord) else { return }
        guard let localEntry = try? await store.get(date: date) else { return }
        let localModifiedAt = localEntry.modifiedAt.map(Self.iso.string(from:)) ?? Self.iso.string(from: Date())
        let contentEqual = localEntry.content == server.content && localEntry.location == server.location
        let systemFields = Self.systemFieldsData(of: serverRecord)

        switch SyncReconciler.resolveConflict(
            localModifiedAt: localModifiedAt,
            localContentEqualsServer: contentEqual,
            server: server
        ) {
        case .localWinsReupload:
            // Adopt the fresh change tag; next batch uploads local content on
            // top of it and wins without another round-trip.
            try? await store.storeSystemFields(date: date, systemFields)
            engine?.state.add(pendingRecordZoneChanges: [.saveRecord(SyncSchema.recordID(dateKey: date))])
        case .remoteWins:
            try? await store.putFromSync(
                date: server.date,
                content: server.content,
                createdAt: server.createdAt,
                location: server.location,
                modifiedAt: server.modifiedAt,
                systemFields: systemFields,
                backupReason: "lww-remote-won"
            )
            let changed = server.date
            await MainActor.run {
                NotificationCenter.default.post(
                    name: .nootEntriesChangedRemotely,
                    object: nil,
                    userInfo: ["dates": Set([changed])]
                )
            }
        case .identical:
            try? await store.markUploaded(date: date, uploadedModifiedAt: server.modifiedAt, systemFields: systemFields)
        }
    }

    // MARK: - Helpers

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func systemFieldsData(of record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        return archiver.encodedData
    }

    private static func record(fromSystemFields data: Data?) -> CKRecord? {
        guard let data else { return nil }
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = true
        return CKRecord(coder: unarchiver)
    }
}
