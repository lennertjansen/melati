import SwiftUI

/// The quiet sync surface: renders nothing when everything is fine, a small
/// subtle line otherwise. Lives in the Entries toolbar on both platforms.
struct SyncStatusLine: View {
    let status: SyncStatus

    var body: some View {
        if let text {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Color("ForegroundSubtle"))
        }
    }

    private var text: String? {
        switch status {
        case .idle:
            return nil
        case .off:
            return String(localized: "sync.off")
        case .syncing:
            return String(localized: "sync.syncing")
        case .error(.quotaFull):
            return String(localized: "sync.quota")
        case .error:
            return String(localized: "sync.error")
        }
    }
}
