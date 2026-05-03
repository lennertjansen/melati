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
            TextField("location", text: $draft)
                .textFieldStyle(.plain)
                .font(.lora(size: 14))
                .foregroundStyle(Color("Foreground"))
                .focused($focused)
                .frame(width: 160)
                .onSubmit { commit() }
                .onExitCommand { cancel() }
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color("ForegroundSubtle").opacity(0.35))
                        .frame(height: 1)
                        .offset(y: 4)
                }
                .overlay(alignment: .topLeading) {
                    if focused && !filteredRecents.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredRecents.prefix(6), id: \.self) { loc in
                                Button {
                                    draft = loc
                                    commit()
                                } label: {
                                    Text(loc)
                                        .font(.lora(size: 13))
                                        .foregroundStyle(Color("Foreground"))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color("Background"))
                                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color("ForegroundSubtle").opacity(0.2), lineWidth: 0.5)
                        )
                        .frame(width: 200)
                        .offset(x: 0, y: 26)
                        .transition(.opacity)
                        .zIndex(100)
                    }
                }
                .onAppear {
                    draft = value ?? ""
                    DispatchQueue.main.async { focused = true }
                }
                .onChange(of: focused) { _, isFocused in
                    guard !isFocused else { return }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(150))
                        if !focused && editing { commit() }
                    }
                }
        } else {
            Button {
                editing = true
            } label: {
                if let v = value, !v.isEmpty {
                    Text(v)
                        .font(.lora(size: 14))
                        .foregroundStyle(Color("ForegroundSubtle"))
                } else {
                    Text("location")
                        .font(.lora(size: 14))
                        .foregroundStyle(Color("ForegroundSubtle").opacity(0.4))
                }
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

    private func cancel() {
        draft = value ?? ""
        editing = false
    }
}
