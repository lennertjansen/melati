import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            for window in NSApplication.shared.windows where window.canBecomeMain {
                window.setFrameAutosaveName("NootMain")
            }
        }
        Task { @MainActor in
            AppEnvironment.shared.startSyncIfAvailable()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Foreground fetch: mac dev builds have no push, this is the backstop.
        Task { @MainActor in
            AppEnvironment.shared.syncFetchNow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        let sem = DispatchSemaphore(value: 0)
        Task { @MainActor in
            await AppEnvironment.shared.flushPending()
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 1.5)
    }
}
