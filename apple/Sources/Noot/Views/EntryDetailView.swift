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
                HStack(spacing: 0) {
                    Button(action: onDismiss) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color("ForegroundSubtle"))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                    .accessibilityLabel(Text(String(localized: "back")))
                    Spacer()
                    #if os(iOS)
                    // Touch has no arrow keys: visible prev/next. Mac keeps
                    // its keyboard-only nav (buttons below).
                    if let onPrev {
                        navChevron("chevron.backward", action: onPrev, label: "entry.older")
                    }
                    if let onNext {
                        navChevron("chevron.forward", action: onNext, label: "entry.newer")
                    }
                    #endif
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

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

                MarkdownEditor(
                    text: .constant(content),
                    readOnly: true,
                    colorScheme: colorScheme
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(
            Group {
                Button(action: onDismiss) { EmptyView() }
                    .keyboardShortcut("[", modifiers: [.command])
                Button { onPrev?() } label: { EmptyView() }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(onPrev == nil)
                Button { onNext?() } label: { EmptyView() }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(onNext == nil)
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        )
        .task(id: dateKey) {
            await load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nootEntriesChangedRemotely)) { note in
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

    #if os(iOS)
    private func navChevron(_ systemImage: String, action: @escaping () -> Void, label: String.LocalizationValue) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color("ForegroundSubtle"))
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(String(localized: label)))
    }
    #endif

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
