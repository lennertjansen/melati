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
    // What the store last held for this entry: the buffer is "clean" when it
    // matches, and only a clean buffer may be refreshed by a remote change.
    @State private var persistedContent: String = ""
    @State private var persistedLocation: String?
    @State private var remoteUpdateNotice: Bool = false

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
                if remoteUpdateNotice {
                    Text(String(localized: "today.remoteUpdate"))
                        .font(.system(size: 11))
                        .foregroundStyle(Color("ForegroundSubtle"))
                        .padding(.bottom, 6)
                        .transition(.opacity)
                }
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
        .onReceive(NotificationCenter.default.publisher(for: .nootEntriesChangedRemotely)) { note in
            guard let dates = note.userInfo?["dates"] as? Set<String>, dates.contains(dateKey) else { return }
            Task { await applyRemoteChange() }
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
        remoteUpdateNotice = false
        await load()
    }

    /// A remote change for today already landed in the store (the reconciler
    /// merged any fork - older content above). A clean editor refreshes
    /// silently; a dirty one absorbs the unseen content ABOVE what is being
    /// typed - keystrokes are never lost, and neither is the other device's
    /// text.
    private func applyRemoteChange() async {
        guard loaded else { return }
        guard let fresh = try? await env.store.get(date: dateKey) else { return }
        switch RemoteUpdatePolicy.action(
            bufferContent: content,
            bufferLocation: existingLocation,
            persistedContent: persistedContent,
            persistedLocation: persistedLocation
        ) {
        case .refresh:
            content = fresh.content
            existingCreatedAt = fresh.createdAt
            existingLocation = fresh.location
            persistedContent = fresh.content
            persistedLocation = fresh.location
            remoteUpdateNotice = false
        case .notice:
            saveTask?.cancel()
            let buffer = content
            let previousPersisted = persistedContent
            let newBuffer: String
            if EntryMerge.contains(fresh.content, buffer) {
                // Store already absorbed everything in the buffer.
                newBuffer = fresh.content
            } else if EntryMerge.contains(buffer, fresh.content) {
                // Buffer already absorbed the store content.
                newBuffer = buffer
            } else if !previousPersisted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      fresh.content.hasSuffix(previousPersisted) {
                // The reconciler stacked unseen content above our persisted
                // text; swap the trailing persisted block for the live buffer
                // so unsaved keystrokes survive without duplication.
                newBuffer = String(fresh.content.dropLast(previousPersisted.count)) + buffer
            } else {
                // Live keystrokes are newer than anything in the store:
                // unseen content goes above, shared prefix not duplicated.
                newBuffer = EntryMerge.mergeOrdered(older: fresh.content, newer: buffer)
            }
            persistedContent = fresh.content
            persistedLocation = fresh.location
            if existingCreatedAt == nil { existingCreatedAt = fresh.createdAt }
            if newBuffer != content {
                content = newBuffer
                scheduleAutosave()
            }
            withAnimation { remoteUpdateNotice = true }
        }
    }

    private func load() async {
        let key = DateUtil.todayKey()
        dateKey = key
        do {
            if let existing = try await env.store.get(date: key) {
                content = existing.content
                existingCreatedAt = existing.createdAt
                existingLocation = existing.location
                persistedContent = existing.content
                persistedLocation = existing.location
            } else {
                persistedContent = ""
                persistedLocation = nil
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
            persistedContent = entry.content
            persistedLocation = entry.location
            if env.pendingEntry?.date == entry.date && env.pendingEntry?.content == entry.content {
                env.pendingEntry = nil
            }
        } catch {
            print("Save failed: \(error)")
        }
    }
}
