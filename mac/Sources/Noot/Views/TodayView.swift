import SwiftUI

struct TodayView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.colorScheme) private var colorScheme

    @State private var content: String = ""
    @State private var existingCreatedAt: Date?
    @State private var existingLocation: String?
    @State private var loaded: Bool = false
    @State private var saveTask: Task<Void, Never>?
    @State private var dateKey: String = DateUtil.todayKey()
    @State private var recentLocations: [String] = []

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()
            VStack(spacing: 0) {
                header
                    .padding(.top, 24)
                    .padding(.bottom, 8)
                MarkdownEditor(
                    text: $content,
                    readOnly: false,
                    colorScheme: colorScheme,
                    onTextChange: { scheduleAutosave() },
                    onBlur: { Task { await save() } }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await load()
        }
        .onDisappear {
            saveTask?.cancel()
            Task { await save() }
        }
    }

    private var header: some View {
        let parts = DateUtil.formatHeaderParts(dateKey: dateKey, createdAt: existingCreatedAt)
        return HStack(spacing: 8) {
            Text(parts.dayName)
            Text("·")
            Text(parts.dateText)
            Text("·")
            Text(parts.timeText)
            Text("·")
            LocationField(
                value: existingLocation,
                recents: recentLocations,
                readOnly: false,
                onChange: { newLoc in
                    existingLocation = newLoc
                    scheduleAutosave()
                    Task { await save() }
                }
            )
        }
        .font(.lora(size: 14))
        .foregroundStyle(Color("ForegroundSubtle"))
    }

    private func load() async {
        let key = DateUtil.todayKey()
        dateKey = key
        do {
            if let existing = try await env.store.get(date: key) {
                content = existing.content
                existingCreatedAt = existing.createdAt
                existingLocation = existing.location
            } else {
                existingCreatedAt = Date()
            }
            recentLocations = (try? await env.store.loadRecentLocations()) ?? []
        } catch {
            print("Load failed: \(error)")
        }
        loaded = true
    }

    private func scheduleAutosave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            if Task.isCancelled { return }
            await save()
        }
    }

    private func save() async {
        guard loaded else { return }
        let entry = JournalEntry(
            date: dateKey,
            content: content,
            createdAt: existingCreatedAt ?? Date(),
            location: existingLocation
        )
        do {
            try await env.store.put(entry)
        } catch {
            print("Save failed: \(error)")
        }
    }
}
