import SwiftUI

struct IOSAppShell: View {
    @Environment(AppEnvironment.self) private var env
    @State private var selection: NavTab = .today
    @State private var selectedDate: String? = nil
    @State private var entryDates: [String] = []

    init() {
        // Verification hook: `simctl launch ... -melati.initialTab entries`
        // (launch arguments land in UserDefaults). Screenshot tooling has no
        // way to tap the simulator; real launches always start on Today.
        switch UserDefaults.standard.string(forKey: "melati.initialTab") {
        case "entries": _selection = State(initialValue: .entries)
        case "calendar": _selection = State(initialValue: .calendar)
        default: break
        }
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
        .onReceive(NotificationCenter.default.publisher(for: .melatiEntriesChangedRemotely)) { _ in
            // A sync while an entry is open changes what older/newer should
            // step through; keep the navigation dates fresh.
            guard selectedDate != nil else { return }
            Task { entryDates = (try? await env.store.listDates()) ?? [] }
        }
        .onReceive(NotificationCenter.default.publisher(for: .melatiNewEntry)) { _ in
            selectedDate = nil
            selection = .today
        }
        .onReceive(NotificationCenter.default.publisher(for: .melatiSelectTab)) { note in
            if let tab = note.object as? NavTab {
                selectedDate = nil
                selection = tab
            }
        }
    }

    // Same detail model as the mac shell: a selected date replaces the tab's
    // list content. Swipe navigation lives in EntryDetailView.
    @ViewBuilder
    private func detailWrapped<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color("Background").ignoresSafeArea()
            if let date = selectedDate {
                let onDismiss = { selectedDate = nil }
                let onPrev = nav.older(than: date).map { older in { selectedDate = older } }
                let onNext = nav.newer(than: date).map { newer in { selectedDate = newer } }
                if date == DateUtil.todayKey() {
                    TodayView(onDismiss: onDismiss, onPrev: onPrev, onNext: onNext)
                } else {
                    EntryDetailView(
                        dateKey: date,
                        onDismiss: onDismiss,
                        onPrev: onPrev,
                        onNext: onNext
                    )
                }
            } else {
                content()
            }
        }
    }

    private var nav: EntryNavigation {
        EntryNavigation(entryDates: entryDates, todayKey: DateUtil.todayKey())
    }
}
