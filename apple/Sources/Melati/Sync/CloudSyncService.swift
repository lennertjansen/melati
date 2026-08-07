import CloudKit
import Foundation

// The CloudKit adapter: connects the store's sync API (D1) to the pure LWW
// logic (D2) through CKSyncEngine. This file owns all engine interaction;
// nothing else in the app imports CloudKit except JournalRecordCoder.

extension Notification.Name {
    /// Posted on the main actor after remote changes land locally.
    /// userInfo["dates"] is a Set<String> of affected dateKeys.
    static let melatiEntriesChangedRemotely = Notification.Name("MelatiEntriesChangedRemotely")
}

enum SyncSettings {
    static let enabledKey = "melati.sync.enabled"

    /// Kill switch: `defaults write com.lennertjansen.melati melati.sync.enabled -bool NO`
    /// (or the same key in iOS UserDefaults). Defaults to on - sync is core.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }
}

actor CloudSyncService {
    /// Keeps CloudKit imports out of AppEnvironment.
    static func accountAvailable() async -> Bool {
        let status = try? await CKContainer(identifier: "iCloud.com.lennertjansen.melati").accountStatus()
        return status == .available
    }

    private let store: JournalStore
    private let onStatus: @MainActor (SyncStatus) -> Void
    private var engine: CKSyncEngine?
    private var changesTask: Task<Void, Never>?
    private var activity = SyncActivity()
    private var lastPublishedStatus: SyncStatus?

    private static let engineStateKey = "engine_state"
    private static let zoneCreatedKey = "zone_created"
    /// CKRecordID.recordName of the iCloud user we last synced with. A fresh
    /// engine always announces the account via .signIn; without this marker
    /// every fresh start would look like a new account and reset forever.
    private static let accountUserKey = "account_user"

    init(store: JournalStore, onStatus: @escaping @MainActor (SyncStatus) -> Void = { _ in }) {
        self.store = store
        self.onStatus = onStatus
    }

    // MARK: - Lifecycle

    func start() async {
        guard engine == nil else { return }

        var serialization: CKSyncEngine.State.Serialization?
        if let data = try? await store.syncMeta(key: Self.engineStateKey) {
            serialization = try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
        }
        log(serialization == nil ? "engine state: fresh (no serialization)" : "engine state: restored")

        let container = CKContainer(identifier: "iCloud.com.lennertjansen.melati")
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
            log("launch reconcile: re-queueing \(pending.count) pending: \(pending.joined(separator: ", "))")
            engine.state.add(pendingRecordZoneChanges: pending.map { .saveRecord(SyncSchema.recordID(dateKey: $0)) })
        } else {
            log("launch reconcile: nothing pending")
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
        publishStatus()
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
        log("fetchNow: begin")
        do {
            try await engine.fetchChanges()
            log("fetchNow: ok")
            activity.noteSuccess()
        } catch {
            log("fetchChanges failed: \(error)")
            if let ck = error as? CKError, SyncEdgePolicy.fetchFailureIsQuiet(ck.code) {
                // Offline/throttled is a normal state, not an error line.
            } else {
                activity.noteError(.fetchFailed)
            }
        }
        publishStatus()
    }

    private func noteLocalChange(_ change: LocalChange) {
        guard let engine else { return }
        switch change {
        case .entryChanged(let date):
            log("local change queued: \(date)")
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(SyncSchema.recordID(dateKey: date))])
        }
    }

    private func publishStatus() {
        publish(activity.status)
    }

    private func publish(_ status: SyncStatus) {
        guard status != lastPublishedStatus else { return }
        lastPublishedStatus = status
        let callback = onStatus
        Task { @MainActor in callback(status) }
    }

    private func log(_ message: String) {
        print("[melati.sync] \(message)")
        // stdout is fully buffered when redirected to a file; without the
        // flush, hours of diagnosis chased "hangs" that were just unflushed
        // buffers (2026-08-06, the hard way).
        fflush(stdout)
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
            // MUST NOT run inline: handleAccountChange rebuilds the engine
            // and fetches, which calls back into delegate callbacks -
            // awaiting that from inside handleEvent is a CKSyncEngine fatal
            // error ("BUG IN CLIENT OF CLOUDKIT"). Detached task per docs.
            let changeType = change.changeType
            Task.detached { [weak self] in
                await self?.handleAccountChange(changeType)
            }

        case .fetchedDatabaseChanges(let changes):
            for deletion in changes.deletions where deletion.zoneID == SyncSchema.zoneID {
                await handleZoneDeleted()
            }

        case .willFetchChanges:
            log("event: willFetchChanges")
            activity.begin()
            publishStatus()

        case .willSendChanges:
            log("event: willSendChanges")
            activity.begin()
            publishStatus()

        case .didFetchChanges:
            log("event: didFetchChanges")
            activity.end()
            publishStatus()

        case .didSendChanges:
            log("event: didSendChanges")
            activity.end()
            publishStatus()

        case .willFetchRecordZoneChanges, .didFetchRecordZoneChanges:
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

        log("uploading batch: \(pending.count) change(s)")
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
            let syncRow = try? await store.syncRow(date: remote.date)
            let localModifiedAt = local?.modifiedAt.map(Self.iso.string(from:))

            let resolution = SyncReconciler.resolveFetch(
                localModifiedAt: localModifiedAt,
                lastSyncedModifiedAt: syncRow?.lastSyncedModifiedAt,
                localEqualsRemote: local?.content == remote.content && local?.location == remote.location,
                localContainsRemote: EntryMerge.contains(local?.content ?? "", remote.content),
                remoteContainsLocal: EntryMerge.contains(remote.content, local?.content ?? ""),
                remote: remote
            )
            log("fetched \(remote.date): resolution=\(resolution)")
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
                    backupReason: hadLocal ? "superseded-by-remote" : nil
                )
                touched.insert(remote.date)
            case .keepLocalStoreTag:
                try? await store.storeSystemFields(date: remote.date, systemFields)
            case .identical:
                try? await store.markUploaded(date: remote.date, uploadedModifiedAt: remote.modifiedAt, systemFields: systemFields)
            case .mergeAndUpload:
                guard let local else { break }
                log("fork on \(remote.date): merging (older above), re-uploading")
                let merged = EntryMerge.merge(
                    aContent: local.content, aStamp: localModifiedAt ?? "",
                    bContent: remote.content, bStamp: remote.modifiedAt
                )
                // put() stamps fresh + marks pending; the localChanges stream
                // schedules the upload of the merged entry automatically.
                try? await store.put(JournalEntry(
                    date: remote.date,
                    content: merged,
                    createdAt: local.createdAt ?? remote.createdAt.flatMap(Self.iso.date(from:)),
                    location: Self.mergedLocation(localStamp: localModifiedAt, localLocation: local.location, remote: remote)
                ))
                try? await store.storeSystemFields(date: remote.date, systemFields)
                touched.insert(remote.date)
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
                    name: .melatiEntriesChangedRemotely,
                    object: nil,
                    userInfo: ["dates": dates]
                )
            }
        }
    }

    // MARK: - Edge states (D5)

    /// The journal is NEVER purged on account changes. Reset forgets server
    /// associations and marks everything pending; the rebuilt engine uploads
    /// all local entries and fetches the account's records - the reconciler
    /// merges. Runs in a detached task (never inline in handleEvent).
    private func handleAccountChange(_ changeType: CKSyncEngine.Event.AccountChange.ChangeType) async {
        let event: AccountEvent
        var newUser: String?
        switch changeType {
        case .signIn(let currentUser):
            // Fired by every fresh engine for the CURRENT account too: only
            // a genuinely different user warrants a reset.
            let stored = (try? await store.syncMeta(key: Self.accountUserKey))
                .flatMap { String(data: $0, encoding: .utf8) }
            if stored == currentUser.recordName {
                log("account signIn: same user, nothing to do")
                return
            }
            log("account signIn: \(stored == nil ? "no stored user" : "different user") - reset + merge")
            event = .signIn
            newUser = currentUser.recordName
        case .signOut:
            log("account signOut - keep data, reset associations, engine idles")
            event = .signOut
        case .switchAccounts(_, let currentUser):
            log("account switch - reset + merge into new account")
            event = .switchAccounts
            newUser = currentUser.recordName
        @unknown default:
            log("unhandled account change: \(changeType)")
            return
        }

        let plan = SyncEdgePolicy.plan(for: event)
        // Drop the old engine before touching state so nothing uploads
        // against the previous account mid-reset.
        changesTask?.cancel()
        changesTask = nil
        engine = nil
        activity = SyncActivity()

        if plan.resetSyncState {
            try? await store.resetSyncState()
        }
        // After the reset (which wipes sync_meta) so the marker survives.
        if let newUser {
            try? await store.setSyncMeta(key: Self.accountUserKey, value: Data(newUser.utf8))
        }
        if plan.restartEngine {
            await start()
            await fetchNow()
        }
        if let status = plan.statusWhenDone {
            publish(status)
        }
    }

    /// Zone deleted from another device or the dashboard. Local data is the
    /// source of truth: recreate the zone and re-upload everything.
    private func handleZoneDeleted() async {
        log("zone deleted remotely - recreating zone, re-uploading all entries")
        try? await store.resetSyncState()
        engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncSchema.zoneID))])
        if let pending = try? await store.pendingDates(), !pending.isEmpty {
            engine?.state.add(pendingRecordZoneChanges: pending.map { .saveRecord(SyncSchema.recordID(dateKey: $0)) })
        }
    }

    // MARK: - Sent changes <- server verdicts

    private func handleSentChanges(_ sent: CKSyncEngine.Event.SentRecordZoneChanges) async {
        log("sent: \(sent.savedRecords.count) saved (\(sent.savedRecords.map(\.recordID.recordName).joined(separator: ", "))), \(sent.failedRecordSaves.count) failed")
        if !sent.savedRecords.isEmpty && sent.failedRecordSaves.isEmpty {
            activity.noteSuccess()
            publishStatus()
        }
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
            switch SyncEdgePolicy.uploadFailureAction(for: ckError.code) {
            case .resolveConflict:
                await resolveUploadConflict(date: date, serverRecord: ckError.serverRecord)
            case .recreateZone:
                engine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncSchema.zoneID))])
                engine?.state.add(pendingRecordZoneChanges: [.saveRecord(failure.record.recordID)])
            case .quotaFull:
                log("save failed (\(date)): iCloud quota full - keeping pending")
                activity.noteError(.quotaFull)
                publishStatus()
            case .retryQuietly:
                log("save failed (\(date)): \(ckError.code) - engine retries")
            case .retryShowError:
                log("save failed (\(date)): \(ckError.code) - will retry")
                activity.noteError(.uploadFailed)
                publishStatus()
            }
        }
    }

    private func resolveUploadConflict(date: String, serverRecord: CKRecord?) async {
        guard let serverRecord, let server = JournalRecordCoder.decode(serverRecord) else { return }
        guard let localEntry = try? await store.get(date: date) else { return }
        let syncRow = try? await store.syncRow(date: date)
        let localModifiedAt = localEntry.modifiedAt.map(Self.iso.string(from:)) ?? Self.iso.string(from: Date())
        let systemFields = Self.systemFieldsData(of: serverRecord)

        switch SyncReconciler.resolveConflict(
            localModifiedAt: localModifiedAt,
            lastSyncedModifiedAt: syncRow?.lastSyncedModifiedAt,
            localEqualsServer: localEntry.content == server.content && localEntry.location == server.location,
            localContainsServer: EntryMerge.contains(localEntry.content, server.content),
            serverContainsLocal: EntryMerge.contains(server.content, localEntry.content),
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
                backupReason: "superseded-by-remote"
            )
            await postRemoteChange(dates: [server.date])
        case .identical:
            try? await store.markUploaded(date: date, uploadedModifiedAt: server.modifiedAt, systemFields: systemFields)
        case .mergeAndReupload:
            log("fork on \(date) at upload: merging (older above), re-uploading")
            let merged = EntryMerge.merge(
                aContent: localEntry.content, aStamp: localModifiedAt,
                bContent: server.content, bStamp: server.modifiedAt
            )
            try? await store.put(JournalEntry(
                date: date,
                content: merged,
                createdAt: localEntry.createdAt ?? server.createdAt.flatMap(Self.iso.date(from:)),
                location: Self.mergedLocation(localStamp: localModifiedAt, localLocation: localEntry.location, remote: server)
            ))
            try? await store.storeSystemFields(date: date, systemFields)
            engine?.state.add(pendingRecordZoneChanges: [.saveRecord(SyncSchema.recordID(dateKey: date))])
            await postRemoteChange(dates: [date])
        }
    }

    /// Merged entries keep the newer side's location when it has one; the
    /// older side's otherwise. Content merges, location cannot.
    private static func mergedLocation(localStamp: String?, localLocation: String?, remote: RemoteEntry) -> String? {
        let localIsNewer = localStamp.map { SyncReconciler.compare($0, remote.modifiedAt) == .orderedDescending } ?? false
        let newer = localIsNewer ? localLocation : remote.location
        let older = localIsNewer ? remote.location : localLocation
        if let newer, !newer.isEmpty { return newer }
        return older
    }

    private func postRemoteChange(dates: Set<String>) async {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .melatiEntriesChangedRemotely,
                object: nil,
                userInfo: ["dates": dates]
            )
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
