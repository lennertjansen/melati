#if DEBUG
import Foundation

/// Simulator verification hook: `simctl launch ... -noot.seedDemoBackups YES`
/// seeds today's entry plus two conflict backups through the real public
/// store APIs (put + putFromSync with a backup reason - the exact LWW flow).
/// DEBUG-only; screenshot tooling cannot produce a two-device conflict.
enum DebugSeed {
    static func demoBackupsIfRequested() {
        guard UserDefaults.standard.bool(forKey: "noot.seedDemoBackups") else { return }
        let store = AppEnvironment.shared.store
        let key = DateUtil.todayKey()
        Task {
            do {
                try await store.put(JournalEntry(
                    date: key,
                    content: "First draft, written on this phone.",
                    createdAt: Date(),
                    location: "Amsterdam"
                ))
                try await store.putFromSync(
                    date: key,
                    content: "Second version, arrived from the Mac.",
                    createdAt: nil,
                    location: "Amsterdam",
                    modifiedAt: "2026-08-05T10:00:00.000Z",
                    systemFields: Data(),
                    backupReason: "lww-remote-won"
                )
                try await store.putFromSync(
                    date: key,
                    content: "Final synced version of the entry.",
                    createdAt: nil,
                    location: "Utrecht",
                    modifiedAt: "2026-08-05T11:00:00.000Z",
                    systemFields: Data(),
                    backupReason: "lww-remote-won"
                )
                print("[noot.debug] seeded demo backups for \(key)")
            } catch {
                print("[noot.debug] seed failed: \(error)")
            }
        }
    }
}
#endif
