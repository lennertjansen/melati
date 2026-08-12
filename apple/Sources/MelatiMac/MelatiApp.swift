import SwiftUI

@main
struct MelatiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("melati.showPreviews") private var showPreviews: Bool = false

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
            CommandMenu(String(localized: "menu.view")) {
                Button(String(localized: "tab.today")) {
                    NotificationCenter.default.post(name: .melatiSelectTab, object: NavTab.today)
                }
                .keyboardShortcut("1", modifiers: [.command])
                Button(String(localized: "tab.entries")) {
                    NotificationCenter.default.post(name: .melatiSelectTab, object: NavTab.entries)
                }
                .keyboardShortcut("2", modifiers: [.command])
                Button(String(localized: "tab.calendar")) {
                    NotificationCenter.default.post(name: .melatiSelectTab, object: NavTab.calendar)
                }
                .keyboardShortcut("3", modifiers: [.command])
                Divider()
                Toggle(String(localized: "menu.showPreviews"), isOn: $showPreviews)
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Divider()
                Button(String(localized: "cmd.focusLocation")) {
                    NotificationCenter.default.post(name: .melatiFocusLocation, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command])
            }
        }
    }
}
