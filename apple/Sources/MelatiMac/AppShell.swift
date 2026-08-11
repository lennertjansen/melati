import SwiftUI

struct AppShell: View {
    @Environment(AppEnvironment.self) private var env
    @State private var selection: NavTab = .today
    @State private var sidebarVisible: Bool = false
    @State private var selectedDate: String? = nil
    @State private var hideTask: Task<Void, Never>? = nil
    @State private var entryDates: [String] = []

    private let sidebarWidth: CGFloat = 168
    private let edgeTriggerWidth: CGFloat = 28
    private let hideDelay: Duration = .milliseconds(400)

    var body: some View {
        ZStack(alignment: .leading) {
            Color("Background").ignoresSafeArea()

            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // No edge trigger while an entry is open: the sidebar would slide
            // over the back chevron and trap the user (they use Back instead).
            if !sidebarVisible && selectedDate == nil {
                Color.clear
                    .frame(width: edgeTriggerWidth)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering { showSidebar() }
                    }
            }

            // Also gated on selectedDate: the sidebar must be structurally
            // unable to overlay an open entry, not just usually hidden by the
            // hover timer (it could otherwise linger over the back chevron for
            // the hide-delay window when a row is opened mid-hover).
            if sidebarVisible && selectedDate == nil {
                CustomSidebar(selection: selection, onSelect: selectTab)
                    .frame(width: sidebarWidth)
                    .frame(maxHeight: .infinity)
                    .background(
                        Color("Background")
                            .overlay(alignment: .trailing) {
                                Rectangle()
                                    .fill(Color("ForegroundSubtle").opacity(0.12))
                                    .frame(width: 1)
                            }
                    )
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .onHover { hovering in
                        if hovering { cancelHideTimer() } else { scheduleHide() }
                    }
                    .zIndex(10)
            }
        }
        .onChange(of: selection) { _, _ in
            selectedDate = nil
            scheduleHide()
        }
        .onChange(of: selectedDate) { _, new in
            guard new != nil else { return }
            sidebarVisible = false
            cancelHideTimer()
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

    /// Dates reachable by prev/next: every entry plus today (which is always
    /// openable and editable even before it has a row). Sorted newest-first,
    /// matching entryDates. Keeps flipping positional so gaps between entries
    /// are skipped and a rowless today still navigates.
    private var navDates: [String] {
        let today = DateUtil.todayKey()
        guard !entryDates.contains(today) else { return entryDates }
        return ([today] + entryDates).sorted(by: >)
    }

    @ViewBuilder
    private var detailContent: some View {
        if let date = selectedDate {
            let idx = navDates.firstIndex(of: date)
            let onDismiss = { selectedDate = nil }
            let onPrev = olderDate(from: idx).map { older in { selectedDate = older } }
            let onNext = newerDate(from: idx).map { newer in { selectedDate = newer } }
            // Today is always the editable surface, however it was reached.
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
            switch selection {
            case .today:
                TodayView()
            case .entries:
                EntriesListView(onSelectDate: { selectedDate = $0 })
            case .calendar:
                CalendarView(onSelectDate: { selectedDate = $0 })
            }
        }
    }

    private func selectTab(_ tab: NavTab) {
        // Always leave any open entry, even when the tab is unchanged (a plain
        // `selection = tab` would be a no-op and strand the user on the entry).
        selectedDate = nil
        selection = tab
        scheduleHide()
    }

    private func olderDate(from idx: Array<String>.Index?) -> String? {
        guard let idx else { return nil }
        let next = idx + 1
        return navDates.indices.contains(next) ? navDates[next] : nil
    }

    private func newerDate(from idx: Array<String>.Index?) -> String? {
        guard let idx else { return nil }
        let prev = idx - 1
        return navDates.indices.contains(prev) ? navDates[prev] : nil
    }

    private func showSidebar() {
        cancelHideTimer()
        withAnimation(.easeOut(duration: 0.10)) {
            sidebarVisible = true
        }
    }

    private func scheduleHide() {
        cancelHideTimer()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: hideDelay)
            if Task.isCancelled { return }
            withAnimation(.easeIn(duration: 0.16)) {
                sidebarVisible = false
            }
        }
    }

    private func cancelHideTimer() {
        hideTask?.cancel()
        hideTask = nil
    }
}

private struct CustomSidebar: View {
    let selection: NavTab
    let onSelect: (NavTab) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer().frame(height: 32)
            ForEach(NavTab.allCases, id: \.self) { tab in
                row(tab)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
    }

    private func row(_ tab: NavTab) -> some View {
        let isSelected = tab == selection
        return Button {
            onSelect(tab)
        } label: {
            Text(String(localized: tab.labelKey))
                .font(.lora(size: 15, weight: isSelected ? .bold : .regular))
                .foregroundStyle(isSelected ? Color("Foreground") : Color("ForegroundSubtle"))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color("ForegroundSubtle").opacity(0.10) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sidebar.\(tab.rawValue)")
    }
}
