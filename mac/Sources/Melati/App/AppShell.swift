import SwiftUI

enum NavTab: Hashable, CaseIterable {
    case today, entries, calendar

    var labelKey: LocalizedStringResource {
        switch self {
        case .today: return "tab.today"
        case .entries: return "tab.entries"
        case .calendar: return "tab.calendar"
        }
    }
}

struct AppShell: View {
    @State private var selection: NavTab = .today
    @State private var sidebarVisible: Bool = false
    @State private var selectedDate: String? = nil
    @State private var hideTask: Task<Void, Never>? = nil

    private let sidebarWidth: CGFloat = 168
    private let edgeTriggerWidth: CGFloat = 6
    private let hideDelay: Duration = .milliseconds(400)

    var body: some View {
        ZStack(alignment: .leading) {
            Color("Background").ignoresSafeArea()

            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !sidebarVisible {
                Color.clear
                    .frame(width: edgeTriggerWidth)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering { showSidebar() }
                    }
            }

            if sidebarVisible {
                CustomSidebar(selection: $selection)
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
        .onReceive(NotificationCenter.default.publisher(for: .melatiNewEntry)) { _ in
            selectedDate = nil
            selection = .today
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if let date = selectedDate {
            EntryDetailView(dateKey: date) { selectedDate = nil }
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
    @Binding var selection: NavTab

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
            selection = tab
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
    }
}
