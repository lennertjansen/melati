import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()
            VStack(spacing: 12) {
                Text("Noot")
                    .font(.lora(size: 56, weight: .bold))
                    .foregroundStyle(Color("Foreground"))
                Text("Phase 3 — M0 smoke test")
                    .font(.lora(size: 16))
                    .foregroundStyle(Color("ForegroundSubtle"))
            }
        }
        .frame(minWidth: 640, minHeight: 480)
    }
}

#Preview {
    ContentView()
}
