import Foundation
import Observation

@MainActor
@Observable
final class AppEnvironment {
    static let shared = AppEnvironment()

    let store: JournalStore
    var pendingEntry: JournalEntry?

    private init() {
        do {
            let key = try KeyStore.default.loadOrCreate()
            let url = try JournalStore.defaultDatabaseURL()
            self.store = try JournalStore(path: url.path, key: key)
        } catch {
            fatalError("Melati failed to initialize encrypted storage: \(error)")
        }
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
