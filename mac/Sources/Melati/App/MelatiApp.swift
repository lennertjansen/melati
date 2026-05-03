import SwiftUI

extension Notification.Name {
    static let melatiNewEntry = Notification.Name("MelatiNewEntry")
}

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
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(String(localized: "cmd.newEntry")) {
                    NotificationCenter.default.post(name: .melatiNewEntry, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }
    }
}
