import SwiftUI

@main
struct MelatiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        FontRegistry.registerBundledFonts()
        _ = AppEnvironment.shared
    }

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environment(AppEnvironment.shared)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
