import SwiftUI

struct IntelligenceStatusChip: View {
    let snapshot: CatalogIntelligenceStatusSnapshot

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: snapshot.status.icon)
                .font(.system(size: 9, weight: .semibold))
            Text(snapshot.status.rawValue)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(snapshot.status.tint.opacity(0.1))
        )
        .foregroundStyle(snapshot.status.tint)
        .help(helpText)
    }

    private var helpText: String {
        if let error = snapshot.errorMessage, !error.isEmpty {
            return error
        }
        switch snapshot.status {
        case .notFetched:
            return "Intelligence has not been fetched for this catalog item yet."
        case .ready:
            return "Intelligence is ready for compare, graph, and recommendations."
        default:
            return snapshot.status.rawValue
        }
    }
}
