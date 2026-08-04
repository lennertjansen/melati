import SwiftUI

/// Formatting bar pinned above the software keyboard while the editor is
/// focused. iOS only: pinned via safeAreaInset so SwiftUI keyboard avoidance
/// positions it; deliberately NOT a WKContentView inputAccessoryView override
/// (private-class hack that breaks across iOS releases). On macOS this
/// modifier is a no-op - the menu bar owns formatting there.
struct EditorAccessoryBar: ViewModifier {
    let controller: EditorController

    func body(content: Content) -> some View {
        #if os(iOS)
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if controller.isFocused {
                HStack(spacing: 4) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            button("bold", systemImage: "bold")
                            button("italic", systemImage: "italic")
                            button("h1", systemImage: "textformat.size.larger")
                            button("h2", systemImage: "textformat.size")
                            button("bulletList", systemImage: "list.bullet")
                            button("orderedList", systemImage: "list.number")
                            button("blockquote", systemImage: "text.quote")
                        }
                    }
                    Spacer(minLength: 8)
                    Button {
                        controller.done()
                    } label: {
                        Text(String(localized: "editor.done"))
                            .font(.lora(size: 15, weight: .bold))
                            .foregroundStyle(Color("Foreground"))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color("ForegroundSubtle").opacity(0.15))
                        .frame(height: 0.5)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.15), value: controller.isFocused)
        #else
        content
        #endif
    }

    #if os(iOS)
    private func button(_ command: String, systemImage: String) -> some View {
        Button {
            controller.exec(command)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color("Foreground"))
                .frame(width: 40, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    #endif
}

extension View {
    func editorAccessoryBar(_ controller: EditorController) -> some View {
        modifier(EditorAccessoryBar(controller: controller))
    }
}
