import SwiftUI

struct EntryDetailView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.colorScheme) private var colorScheme

    let dateKey: String
    let onDismiss: () -> Void
    var onPrev: (() -> Void)? = nil
    var onNext: (() -> Void)? = nil

    @State private var content: String = ""
    @State private var createdAt: Date?
    @State private var location: String?
    @State private var loaded: Bool = false

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()
            VStack(spacing: 0) {
                EntryNavBar(onDismiss: onDismiss, onPrev: onPrev, onNext: onNext)

                EntryHeader(
                    dateKey: dateKey,
                    createdAt: createdAt,
                    location: location,
                    recents: [],
                    locationSuggestion: nil,
                    readOnly: true,
                    onLocationChange: nil
                )
                .padding(.top, 12)
                .padding(.bottom, 8)
                .accessibilityIdentifier("entry.header.\(dateKey)")

                MarkdownEditor(
                    text: .constant(content),
                    readOnly: true,
                    colorScheme: colorScheme
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("editor.readonly")
            }
        }
        .background(
            Button(action: onDismiss) { EmptyView() }
                .keyboardShortcut("[", modifiers: [.command])
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        )
        .task(id: dateKey) {
            await load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .melatiEntriesChangedRemotely)) { note in
            // Read-only view: refreshing can never stomp anything.
            guard let dates = note.userInfo?["dates"] as? Set<String>, dates.contains(dateKey) else { return }
            Task { await load() }
        }
        #if os(iOS)
        // Horizontal swipe = prev/next entry; swipe right past the oldest
        // dismisses (mirrors the reading direction of the chevrons). High
        // priority so the read-only webview doesn't swallow the gesture.
        .highPriorityGesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    if value.translation.width < 0 {
                        onNext?()
                    } else if let onPrev {
                        onPrev()
                    } else {
                        onDismiss()
                    }
                }
        )
        #endif
    }

    private func load() async {
        do {
            if let entry = try await env.store.get(date: dateKey) {
                content = entry.content
                createdAt = entry.createdAt
                location = entry.location
            }
        } catch {
            print("EntryDetailView load failed: \(error)")
        }
        loaded = true
    }
}
