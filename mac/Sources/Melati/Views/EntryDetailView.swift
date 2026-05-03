import SwiftUI

struct EntryDetailView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.colorScheme) private var colorScheme

    let dateKey: String
    let onDismiss: () -> Void

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
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                EntryHeader(
                    dateKey: dateKey,
                    createdAt: createdAt,
                    location: location,
                    recents: [],
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
        .task(id: dateKey) {
            await load()
        }
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
