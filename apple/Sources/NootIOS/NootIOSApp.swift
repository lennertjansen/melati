import SwiftUI
import UIKit

@main
struct NootIOSApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FontRegistry.registerBundledFonts()
        _ = AppEnvironment.shared
    }

    var body: some Scene {
        WindowGroup {
            IOSAppShell()
                .environment(AppEnvironment.shared)
        }
        .onChange(of: scenePhase) { _, phase in
            // iOS has no reliable terminate hook (mac uses
            // applicationWillTerminate): flush on every backgrounding, under a
            // background task so the write survives an immediate suspend.
            guard phase == .background else { return }
            var taskID: UIBackgroundTaskIdentifier = .invalid
            taskID = UIApplication.shared.beginBackgroundTask(withName: "noot.flush") {
                UIApplication.shared.endBackgroundTask(taskID)
            }
            Task {
                await AppEnvironment.shared.flushPending()
                UIApplication.shared.endBackgroundTask(taskID)
            }
        }
    }
}
