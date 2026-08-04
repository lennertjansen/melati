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
    @State private var editorController = EditorController()

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()
            VStack(spacing: 0) {
                EntryHeader(
                    dateKey: dateKey,
                    createdAt: existingCreatedAt,
                    location: existingLocation,
                    recents: recentLocations,
                    locationSuggestion: locationSuggestion,
                    readOnly: false,
                    onLocationChange: { newLoc in
                        existingLocation = newLoc
                        scheduleAutosave()
                        Task { await save() }
                    }
                )
                .padding(.top, 24)
                .padding(.bottom, 8)
                MarkdownEditor(
                    text: $content,
                    readOnly: false,
                    colorScheme: colorScheme,
                    controller: editorController,
                    onTextChange: { scheduleAutosave() },
                    onBlur: { Task { await save() } }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .editorAccessoryBar(editorController)
        .overlayPreferenceValue(LocationDropdownContextKey.self) { context in
            LocationDropdownOverlay(context: context)
        }
        .task {
            await load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            Task { await rollOverToToday() }
        }
        .onDisappear {
            saveTask?.cancel()
            Task { await save() }
        }
    }

    private func rollOverToToday() async {
        guard DateUtil.todayKey() != dateKey else { return }
        saveTask?.cancel()
        await save()
        loaded = false
        content = ""
        existingCreatedAt = nil
        existingLocation = nil
        await load()
    }

    private func load() async {
        let key = DateUtil.todayKey()
        dateKey = key
        do {
            if let existing = try await env.store.get(date: key) {
                content = existing.content
                existingCreatedAt = existing.createdAt
                existingLocation = existing.location
            }
            recentLocations = (try? await env.store.loadRecentLocations()) ?? []
        } catch {
            print("Load failed: \(error)")
        }
        loaded = true
    }

    private var locationSuggestion: String? {
        guard (existingLocation ?? "").isEmpty else { return nil }
        return recentLocations.first
    }

    private func currentEntry() -> JournalEntry {
        JournalEntry(
            date: dateKey,
            content: content,
            createdAt: existingCreatedAt ?? Date(),
            location: existingLocation
        )
    }

    private func scheduleAutosave() {
        // createdAt marks when writing started: stamp on first edit, not on view load
        if existingCreatedAt == nil { existingCreatedAt = Date() }
        env.pendingEntry = currentEntry()
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            if Task.isCancelled { return }
            await save()
        }
    }

    private func save() async {
        guard loaded else { return }
        // never edited and nothing to persist: don't create an empty entry
        // (blur/disappear fire save() even on untouched days)
        if existingCreatedAt == nil && content.isEmpty && (existingLocation ?? "").isEmpty { return }
        let entry = currentEntry()
        do {
            try await env.store.put(entry)
            if env.pendingEntry?.date == entry.date && env.pendingEntry?.content == entry.content {
                env.pendingEntry = nil
            }
        } catch {
            print("Save failed: \(error)")
        }
    }
}
