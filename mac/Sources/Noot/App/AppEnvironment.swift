import Foundation
import Observation

@MainActor
@Observable
final class AppEnvironment {
    let store: JournalStore

    init() {
        do {
            let key = try KeyStore.default.loadOrCreate()
            let url = try JournalStore.defaultDatabaseURL()
            self.store = try JournalStore(path: url.path, key: key)
        } catch {
            fatalError("Noot failed to initialize encrypted storage: \(error)")
        }
    }
}
