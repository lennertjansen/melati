import SwiftUI

struct CalendarView: View {
    @Environment(AppEnvironment.self) private var env

    let onSelectDate: (String) -> Void

    @State private var year: Int = Calendar.current.component(.year, from: Date())
    @State private var month: Int = Calendar.current.component(.month, from: Date())
    @State private var summariesByDate: [String: EntrySummary] = [:]
    @State private var loaded: Bool = false

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()
            VStack(spacing: 0) {
                monthNav
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                weekdayHeader
                    .padding(.horizontal, 24)
                    .padding(.bottom, 4)

                grid
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
        .task {
            await load()
        }
    }

    private var monthNav: some View {
        HStack(spacing: 12) {
            Button(action: prevMonth) {
                Image(systemName: "chevron.left")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(String(localized: "cal.prev")))

            Text(DateUtil.formatMonthYear(year: year, month: month))
                .font(.lora(size: 18))
                .foregroundStyle(Color("Foreground"))

            Button(action: nextMonth) {
                Image(systemName: "chevron.right")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(String(localized: "cal.next")))

            Spacer()
        }
        .foregroundStyle(Color("ForegroundSubtle"))
    }

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(DateUtil.getWeekdayLabels()) { label in
                Text(label.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color("ForegroundSubtle"))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        let days = DateUtil.getMonthDays(year: year, month: month)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(days) { day in
                cell(for: day)
            }
        }
    }

    private func cell(for day: DateUtil.MonthDay) -> some View {
        let dayNum = Calendar.current.component(.day, from: day.date)
        let isToday = day.dateKey == DateUtil.todayKey()
        let summary = summariesByDate[day.dateKey]
        let hasEntry = summary != nil
        let clickable = hasEntry || isToday

        return Button {
            if hasEntry {
                onSelectDate(day.dateKey)
            } else if isToday {
                onSelectDate(day.dateKey)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                ZStack {
                    if isToday {
                        Circle()
                            .fill(Color("Foreground"))
                            .frame(width: 22, height: 22)
                    }
                    Text("\(dayNum)")
                        .font(.system(size: 12, weight: isToday ? .semibold : .regular))
                        .foregroundStyle(
                            isToday ? Color("Background") : Color("Foreground")
                        )
                }
                .frame(width: 22, height: 22)

                if let summary, !summary.preview.isEmpty {
                    Text(summary.preview)
                        .font(.lora(size: 11))
                        .foregroundStyle(Color("ForegroundSubtle"))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(hasEntry ? Color("ForegroundSubtle").opacity(0.06) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!clickable)
        .opacity(day.isCurrentMonth ? 1.0 : 0.45)
    }

    private func prevMonth() {
        if month == 1 {
            month = 12
            year -= 1
        } else {
            month -= 1
        }
    }

    private func nextMonth() {
        if month == 12 {
            month = 1
            year += 1
        } else {
            month += 1
        }
    }

    private func load() async {
        do {
            let all = try await env.store.loadSummaries()
            var dict: [String: EntrySummary] = [:]
            for s in all { dict[s.date] = s }
            summariesByDate = dict
        } catch {
            print("CalendarView load failed: \(error)")
        }
        loaded = true
    }
}
