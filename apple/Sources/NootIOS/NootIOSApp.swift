import SwiftUI
import UIKit

@main
struct NootIOSApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FontRegistry.registerBundledFonts()
        _ = AppEnvironment.shared
        #if DEBUG
        DebugSeed.demoBackupsIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            IOSAppShell()
                .environment(AppEnvironment.shared)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                AppEnvironment.shared.startSyncIfAvailable()
                AppEnvironment.shared.syncFetchNow()
            }
            // iOS has no reliable terminate hook (mac uses
            // applicationWillTerminate): flush on every backgrounding, under a
            // background task so the write survives an immediate suspend.
            guard phase == .background else { return }
            // Box avoids mutating a captured var in the Sendable expiration
            // closure (Swift concurrency warning); the box itself is immutable.
            final class TaskBox: @unchecked Sendable {
                var id: UIBackgroundTaskIdentifier = .invalid
            }
            let box = TaskBox()
            box.id = UIApplication.shared.beginBackgroundTask(withName: "noot.flush") {
                UIApplication.shared.endBackgroundTask(box.id)
            }
            Task {
                await AppEnvironment.shared.flushPending()
                UIApplication.shared.endBackgroundTask(box.id)
            }
        }
    }
}
