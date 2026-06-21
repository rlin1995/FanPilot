import SwiftUI

struct SectionHeader: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

func temperatureColor(_ value: Double) -> Color {
    switch value {
    case 90...:
        return .red
    case 80..<90:
        return .orange
    case 65..<80:
        return .yellow
    default:
        return .primary
    }
}
