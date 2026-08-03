import SwiftUI

@main
struct NootApp: App {
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
                    NotificationCenter.default.post(name: .nootNewEntry, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            CommandMenu(String(localized: "menu.view")) {
                Button(String(localized: "tab.today")) {
                    NotificationCenter.default.post(name: .nootSelectTab, object: NavTab.today)
                }
                .keyboardShortcut("1", modifiers: [.command])
                Button(String(localized: "tab.entries")) {
                    NotificationCenter.default.post(name: .nootSelectTab, object: NavTab.entries)
                }
                .keyboardShortcut("2", modifiers: [.command])
                Button(String(localized: "tab.calendar")) {
                    NotificationCenter.default.post(name: .nootSelectTab, object: NavTab.calendar)
                }
                .keyboardShortcut("3", modifiers: [.command])
                Divider()
                Button(String(localized: "cmd.focusLocation")) {
                    NotificationCenter.default.post(name: .nootFocusLocation, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command])
            }
        }
    }
}
