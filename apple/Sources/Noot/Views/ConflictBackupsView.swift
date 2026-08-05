import SwiftUI

// Read-only browser for an entry's conflict_backups rows: every revision
// whole-entry LWW ever overwrote. Nothing here mutates - restoring is a
// deliberate copy-paste by the user, not a one-tap footgun.

struct ConflictBackupsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.colorScheme) private var colorScheme

    let dateKey: String
    let onDismiss: () -> Void

    @State private var backups: [ConflictBackup] = []
    @State private var selected: ConflictBackup?

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button(action: { selected == nil ? onDismiss() : (selected = nil) }) {
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
                    Text(String(localized: "backups.title"))
                        .font(.lora(size: 14))
                        .foregroundStyle(Color("ForegroundSubtle"))
                    Spacer()
                    // Balances the back button so the title stays centered.
                    Color.clear.frame(width: 28, height: 28)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                if let selected {
                    detail(selected)
                } else {
                    list
                }
            }
        }
        .task {
            backups = ((try? await env.store.conflictBackups(for: dateKey)) ?? []).reversed()
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(backups.enumerated()), id: \.offset) { _, backup in
                    row(backup)
                    Divider().opacity(0.3)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func row(_ backup: ConflictBackup) -> some View {
        Button {
            selected = backup
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(DateUtil.formatSyncTimestamp(backup.backedUpAt))
                        .font(.lora(size: 15))
                        .foregroundStyle(Color("Foreground"))
                    Spacer()
                }
                Text(reasonLabel(backup.reason))
                    .font(.system(size: 11))
                    .foregroundStyle(Color("ForegroundSubtle"))
                let preview = EntryUtil.extractPreview(from: backup.content)
                if !preview.isEmpty {
                    Text(preview)
                        .font(.lora(size: 13))
                        .foregroundStyle(Color("ForegroundSubtle"))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func detail(_ backup: ConflictBackup) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                Text(DateUtil.formatSyncTimestamp(backup.backedUpAt))
                if let loc = backup.location, !loc.isEmpty {
                    Text(loc)
                }
            }
            .font(.lora(size: 13))
            .foregroundStyle(Color("ForegroundSubtle"))
            .padding(.bottom, 8)

            MarkdownEditor(
                text: .constant(backup.content),
                readOnly: true,
                colorScheme: colorScheme
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func reasonLabel(_ reason: String) -> String {
        switch reason {
        case "lww-remote-won":
            return String(localized: "backups.reason.lwwRemoteWon")
        case "remote-delete":
            return String(localized: "backups.reason.remoteDelete")
        default:
            return reason
        }
    }
}
