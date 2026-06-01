import SwiftUI

struct CompareMatrixView: View {
    let result: RepositoryComparisonResult

    private var winnerID: String? { result.rankings.first?.repositoryID }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Comparison matrix")
                .font(.system(size: 12, weight: .semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header row
                    HStack(spacing: 0) {
                        Text("Signal")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 140, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                        ForEach(result.profiles) { profile in
                            let isWinner = profile.repositoryID == winnerID
                            HStack(spacing: 4) {
                                if isWinner {
                                    Image(systemName: "trophy.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.yellow)
                                }
                                Text(profile.fullName)
                                    .font(.system(size: 10, weight: .semibold))
                                    .lineLimit(2)
                            }
                            .frame(width: 160, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(isWinner ? Color.accentColor.opacity(0.12) : .clear)
                        }
                    }
                    .background(Color.primary.opacity(0.05))

                    ForEach(Array(result.matrixRows.enumerated()), id: \.element.id) { index, row in
                        HStack(alignment: .top, spacing: 0) {
                            Text(row.label)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 140, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                            ForEach(result.profiles) { profile in
                                let isWinner = profile.repositoryID == winnerID
                                Text(row.values[profile.repositoryID] ?? "—")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.primary.opacity(0.86))
                                    .frame(width: 160, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .background(isWinner ? Color.accentColor.opacity(0.06) : .clear)
                            }
                        }
                        .background(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.025))
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.03)))
    }
}
