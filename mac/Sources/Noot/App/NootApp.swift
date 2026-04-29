import SwiftUI

@main
struct NootApp: App {
    @State private var env: AppEnvironment

    init() {
        FontRegistry.registerBundledFonts()
        _env = State(initialValue: AppEnvironment())
    }

    var body: some Scene {
        WindowGroup {
            TodayView()
                .environment(env)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
