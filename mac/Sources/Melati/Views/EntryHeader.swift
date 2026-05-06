import SwiftUI

struct EntryHeader: View {
    let dateKey: String
    let createdAt: Date?
    let location: String?
    let recents: [String]
    let locationSuggestion: String?
    let readOnly: Bool
    let onLocationChange: ((String) -> Void)?

    var body: some View {
        let parts = DateUtil.formatHeaderParts(dateKey: dateKey, createdAt: createdAt)
        HStack(spacing: 8) {
            Text(parts.dayName)
            Text("·")
            Text(parts.dateText)
            Text("·")
            Text(parts.timeText)
            if readOnly {
                if let location, !location.isEmpty {
                    Text("·")
                    Text(location)
                }
            } else {
                Text("·")
                LocationField(
                    value: location,
                    recents: recents,
                    suggestion: locationSuggestion,
                    readOnly: false,
                    onChange: { onLocationChange?($0) }
                )
            }
        }
        .font(.lora(size: 14))
        .foregroundStyle(Color("ForegroundSubtle"))
    }
}
