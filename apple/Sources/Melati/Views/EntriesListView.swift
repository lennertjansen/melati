import SwiftUI

struct EntriesListView: View {
    @Environment(AppEnvironment.self) private var env

    let onSelectDate: (String) -> Void

    @AppStorage("melati.listGrouping") private var groupingRaw: String = "flat"
    @AppStorage("melati.showPreviews") private var showPreviews: Bool = false
    @State private var summaries: [EntrySummary] = []
    @State private var loaded: Bool = false

    private enum Grouping: String { case flat, grouped }

    private var grouping: Grouping {
        get { Grouping(rawValue: groupingRaw) ?? .flat }
    }

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()
            VStack(spacing: 0) {
                toolbar
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                if loaded && summaries.isEmpty {
                    Spacer()
                    Text(String(localized: "list.empty"))
                        .font(.lora(size: 18))
                        .foregroundStyle(Color("ForegroundSubtle"))
                    Spacer()
                } else {
                    listBody
                }
            }
        }
        .task {
            await load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .melatiEntriesChangedRemotely)) { _ in
            Task { await load() }
        }
    }

    private var toolbar: some View {
        HStack {
            Picker("", selection: Binding(
                get: { grouping },
                set: { groupingRaw = $0.rawValue }
            )) {
                Text(String(localized: "list.flat")).tag(Grouping.flat)
                Text(String(localized: "list.grouped")).tag(Grouping.grouped)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            Spacer()
            SyncStatusLine(status: env.syncStatus)
        }
    }

    @ViewBuilder
    private var listBody: some View {
        switch grouping {
        case .flat:
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(summaries) { summary in
                        row(summary)
                        Divider().opacity(0.3)
                    }
                }
                .padding(.horizontal, 24)
            }
        case .grouped:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    ForEach(monthGroups, id: \.month) { group in
                        Text(monthLabel(group.month))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color("ForegroundSubtle"))
                            .padding(.top, 16)
                            .padding(.bottom, 6)
                            .padding(.horizontal, 24)
                        ForEach(group.entries) { summary in
                            row(summary)
                            Divider().opacity(0.3)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    private func row(_ summary: EntrySummary) -> some View {
        Button {
            onSelectDate(summary.date)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(DateUtil.formatRelativeDate(dateKey: summary.date))
                        .font(.lora(size: 16))
                        .foregroundStyle(Color("Foreground"))
                    // Location is user-authored entry content and can be as
                    // revealing as the body - same privacy gate as previews.
                    if showPreviews, let loc = summary.location, !loc.isEmpty {
                        Text("·")
                            .foregroundStyle(Color("ForegroundSubtle"))
                        Text(loc)
                            .font(.lora(size: 13))
                            .foregroundStyle(Color("ForegroundSubtle"))
                    }
                    Spacer()
                }
                if showPreviews, !summary.preview.isEmpty {
                    Text(summary.preview)
                        .font(.lora(size: 14))
                        .foregroundStyle(Color("ForegroundSubtle"))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("entries.row.\(summary.date)")
    }

    private struct MonthGroup {
        let month: String
        let entries: [EntrySummary]
    }

    private var monthGroups: [MonthGroup] {
        var ordered: [String] = []
        var byMonth: [String: [EntrySummary]] = [:]
        for s in summaries {
            let mk = String(s.date.prefix(7))
            if byMonth[mk] == nil {
                ordered.append(mk)
                byMonth[mk] = []
            }
            byMonth[mk]?.append(s)
        }
        return ordered.map { MonthGroup(month: $0, entries: byMonth[$0] ?? []) }
    }

    private func monthLabel(_ monthKey: String) -> String {
        let parts = monthKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return monthKey }
        return DateUtil.formatMonthYear(year: parts[0], month: parts[1]).uppercased()
    }

    private func load() async {
        do {
            summaries = try await env.store.loadSummaries()
        } catch {
            print("EntriesListView load failed: \(error)")
        }
        loaded = true
    }
}
