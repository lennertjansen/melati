import SwiftUI

struct IOSAppShell: View {
    @Environment(AppEnvironment.self) private var env
    @State private var selection: NavTab = .today
    @State private var selectedDate: String? = nil
    @State private var entryDates: [String] = []
    #if DEBUG
    // Verification-only: renders ConflictBackupsView directly (no tap path
    // exists for screenshot tooling). Set via `-noot.showBackups <dateKey>`.
    @State private var debugBackupsDate: String? = nil
    #endif

    init() {
        // Verification hooks: `simctl launch ... -noot.initialTab entries`
        // / `-noot.openDate 2026-08-05` (launch arguments land in
        // UserDefaults). Screenshot tooling has no way to tap the simulator;
        // real launches always start on Today with nothing selected.
        switch UserDefaults.standard.string(forKey: "noot.initialTab") {
        case "entries": _selection = State(initialValue: .entries)
        case "calendar": _selection = State(initialValue: .calendar)
        default: break
        }
        if let date = UserDefaults.standard.string(forKey: "noot.openDate") {
            _selection = State(initialValue: .entries)
            _selectedDate = State(initialValue: date)
        }
        #if DEBUG
        _debugBackupsDate = State(initialValue: UserDefaults.standard.string(forKey: "noot.showBackups"))
        #endif
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                TodayView()
                    .background(Color("Background").ignoresSafeArea())
            }
            .tabItem { Label(String(localized: NavTab.today.labelKey), systemImage: "sun.max") }
            .tag(NavTab.today)

            NavigationStack {
                detailWrapped {
                    EntriesListView(onSelectDate: { selectedDate = $0 })
                }
            }
            .tabItem { Label(String(localized: NavTab.entries.labelKey), systemImage: "list.bullet") }
            .tag(NavTab.entries)

            NavigationStack {
                detailWrapped {
                    CalendarView(onSelectDate: { selectedDate = $0 })
                }
            }
            .tabItem { Label(String(localized: NavTab.calendar.labelKey), systemImage: "calendar") }
            .tag(NavTab.calendar)
        }
        .tint(Color("Foreground"))
        .onChange(of: selection) { _, _ in
            selectedDate = nil
        }
        .onChange(of: selectedDate) { _, new in
            guard new != nil else { return }
            Task { entryDates = (try? await env.store.listDates()) ?? [] }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nootNewEntry)) { _ in
            selectedDate = nil
            selection = .today
        }
        .onReceive(NotificationCenter.default.publisher(for: .nootSelectTab)) { note in
            if let tab = note.object as? NavTab {
                selectedDate = nil
                selection = tab
            }
        }
        #if DEBUG
        .overlay {
            if let date = debugBackupsDate {
                ConflictBackupsView(dateKey: date, onDismiss: { debugBackupsDate = nil })
                    .background(Color("Background").ignoresSafeArea())
            }
        }
        #endif
    }

    // Same detail model as the mac shell: a selected date replaces the tab's
    // list content. Swipe-back arrives in C2; onDismiss covers it for now.
    @ViewBuilder
    private func detailWrapped<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color("Background").ignoresSafeArea()
            if let date = selectedDate {
                let idx = entryDates.firstIndex(of: date)
                EntryDetailView(
                    dateKey: date,
                    onDismiss: { selectedDate = nil },
                    onPrev: olderDate(from: idx).map { older in { selectedDate = older } },
                    onNext: newerDate(from: idx).map { newer in { selectedDate = newer } }
                )
            } else {
                content()
            }
        }
    }

    private func olderDate(from idx: Array<String>.Index?) -> String? {
        guard let idx else { return nil }
        let next = idx + 1
        return entryDates.indices.contains(next) ? entryDates[next] : nil
    }

    private func newerDate(from idx: Array<String>.Index?) -> String? {
        guard let idx else { return nil }
        let prev = idx - 1
        return entryDates.indices.contains(prev) ? entryDates[prev] : nil
    }
}
