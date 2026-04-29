import SwiftUI

struct LocationField: View {
    var value: String?
    var recents: [String]
    var readOnly: Bool = false
    var onChange: (String) -> Void

    @State private var editing = false
    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        if readOnly {
            if let v = value, !v.isEmpty {
                Text(v)
                    .font(.lora(size: 14))
                    .foregroundStyle(Color("ForegroundSubtle"))
            }
        } else if editing {
            HStack(spacing: 4) {
                TextField("", text: $draft, onCommit: commit)
                    .textFieldStyle(.plain)
                    .font(.lora(size: 14))
                    .foregroundStyle(Color("Foreground"))
                    .focused($focused)
                    .frame(width: 140)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color("ForegroundSubtle"))
                            .frame(height: 1)
                            .offset(y: 4)
                    }
                    .onExitCommand { editing = false }
            }
            .popover(isPresented: .constant(!filteredRecents.isEmpty && focused), arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredRecents.prefix(6), id: \.self) { loc in
                        Button {
                            draft = loc
                            commit()
                        } label: {
                            Text(loc)
                                .font(.lora(size: 13))
                                .foregroundStyle(Color("Foreground"))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(minWidth: 160)
            }
            .onAppear {
                draft = value ?? ""
                DispatchQueue.main.async { focused = true }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
        } else {
            Button {
                editing = true
            } label: {
                Text(value ?? "+ location")
                    .font(.lora(size: 14))
                    .foregroundStyle(Color("ForegroundSubtle"))
            }
            .buttonStyle(.plain)
        }
    }

    private var filteredRecents: [String] {
        let q = draft.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return recents }
        return recents.filter { $0.lowercased().contains(q) }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed != value {
            onChange(trimmed)
        }
        editing = false
    }
}
