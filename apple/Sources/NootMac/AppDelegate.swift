import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            for window in NSApplication.shared.windows where window.canBecomeMain {
                window.setFrameAutosaveName("NootMain")
            }
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
