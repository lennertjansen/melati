import SwiftUI

struct LocationDropdownContext {
    let anchor: Anchor<CGRect>
    let draft: String
    let recents: [String]
    let onSelect: (String) -> Void
}

struct LocationDropdownContextKey: PreferenceKey {
    static var defaultValue: LocationDropdownContext? = nil
    static func reduce(value: inout LocationDropdownContext?, nextValue: () -> LocationDropdownContext?) {
        if let next = nextValue() { value = next }
    }
}

struct LocationField: View {
    var value: String?
    var recents: [String]
    var suggestion: String? = nil
    var readOnly: Bool = false
    var onChange: (String) -> Void

    @State private var editing = false
    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            content
        }
        .onReceive(NotificationCenter.default.publisher(for: .nootFocusLocation)) { _ in
            guard !readOnly else { return }
            if !editing { editing = true } else { focused = true }
        }
    }

    @ViewBuilder
    private var content: some View {
        if readOnly {
            if let v = value, !v.isEmpty {
                Text(v)
                    .font(.lora(size: 14))
                    .foregroundStyle(Color("ForegroundSubtle"))
            }
        } else if editing {
            TextField(String(localized: "location"), text: $draft)
                .textFieldStyle(.plain)
                .font(.lora(size: 14))
                .foregroundStyle(Color("Foreground"))
                .focused($focused)
                .frame(width: 160)
                .onSubmit { commit() }
                .onEscape { cancel() }
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color("ForegroundSubtle").opacity(0.35))
                        .frame(height: 1)
                        .offset(y: 4)
                }
                .anchorPreference(key: LocationDropdownContextKey.self, value: .bounds) { anchor in
                    LocationDropdownContext(
                        anchor: anchor,
                        draft: draft,
                        recents: recents,
                        onSelect: { picked in
                            draft = picked
                            commit()
                        }
                    )
                }
                .onAppear {
                    draft = (value?.isEmpty == false ? value : nil) ?? suggestion ?? ""
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
                } else if let s = suggestion, !s.isEmpty {
                    Text(s)
                        .font(.lora(size: 14).italic())
                        .foregroundStyle(Color("ForegroundSubtle").opacity(0.55))
                } else {
                    Text(String(localized: "location"))
                        .font(.lora(size: 14))
                        .foregroundStyle(Color("ForegroundSubtle").opacity(0.4))
                }
            }
            .buttonStyle(.plain)
        }
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

private extension View {
    /// Escape-to-cancel. `.onExitCommand` does not exist on iOS; escape there
    /// only matters with a hardware keyboard, handled later if ever needed.
    @ViewBuilder
    func onEscape(perform action: @escaping () -> Void) -> some View {
        #if os(macOS)
        onExitCommand(perform: action)
        #else
        self
        #endif
    }
}

struct LocationDropdownOverlay: View {
    let context: LocationDropdownContext?

    var body: some View {
        GeometryReader { proxy in
            if let context, let filtered = filter(context), !filtered.isEmpty {
                let frame = proxy[context.anchor]
                #if os(iOS)
                // Touch: full-width horizontal chip row under the header -
                // a floating point-anchored list is a mouse idiom.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filtered.prefix(6), id: \.self) { loc in
                            Button {
                                context.onSelect(loc)
                            } label: {
                                Text(loc)
                                    .font(.lora(size: 13))
                                    .foregroundStyle(Color("Foreground"))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule()
                                            .fill(Color("ForegroundSubtle").opacity(0.10))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(maxWidth: .infinity)
                .offset(y: frame.maxY + 10)
                #else
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(filtered.prefix(6), id: \.self) { loc in
                        Button {
                            context.onSelect(loc)
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
                .frame(width: 200, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color("Background"))
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color("ForegroundSubtle").opacity(0.2), lineWidth: 0.5)
                )
                // Clamp so the 200pt dropdown never runs off the right edge
                // (latent on wide mac windows, guaranteed at iPhone widths).
                .offset(x: max(8, min(frame.minX, proxy.size.width - 200 - 8)), y: frame.maxY + 8)
                #endif
            }
        }
        .allowsHitTesting(context != nil)
    }

    private func filter(_ ctx: LocationDropdownContext) -> [String]? {
        let q = ctx.draft.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return ctx.recents }
        return ctx.recents.filter { $0.lowercased().contains(q) }
    }
}
