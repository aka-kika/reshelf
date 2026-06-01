import SwiftUI

struct CatalogRunbookBadgeView: View {
    let badge: CatalogRunbookBadge
    var tooltip: String?

    var body: some View {
        Text(badge.rawValue)
            .font(.system(size: 9, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(tint.opacity(0.1))
            )
            .foregroundStyle(tint)
            .help(tooltip ?? badge.rawValue)
    }

    private var tint: Color {
        switch badge {
        case .noIntelligence:
            return .secondary
        case .generating:
            return .blue
        case .neverGenerated:
            return .orange
        case .freshRunbook:
            return .green
        case .staleRunbook:
            return .yellow
        }
    }
}
