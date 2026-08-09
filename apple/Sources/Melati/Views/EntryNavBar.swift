import SwiftUI

/// Shared top navigation bar for a single opened entry: a back chevron plus
/// optional older/newer chevrons. Used by both the read-only detail view and
/// the editable Today view when it is browsed into, so prev/next entry
/// navigation looks and behaves identically on macOS and iOS.
struct EntryNavBar: View {
    let onDismiss: () -> Void
    var onPrev: (() -> Void)? = nil
    var onNext: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            chevronButton("chevron.left", action: onDismiss,
                          label: "back", id: "entry.back")
                .keyboardShortcut(.escape, modifiers: [])
            Spacer()
            if let onPrev {
                chevronButton("chevron.backward", action: onPrev,
                              label: "entry.older", id: "entry.older")
            }
            if let onNext {
                chevronButton("chevron.forward", action: onNext,
                              label: "entry.newer", id: "entry.newer")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private func chevronButton(
        _ systemImage: String,
        action: @escaping () -> Void,
        label: String.LocalizationValue,
        id: String
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color("ForegroundSubtle"))
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(String(localized: label)))
        .accessibilityIdentifier(id)
    }
}
