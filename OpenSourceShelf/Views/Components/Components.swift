import SwiftUI

struct StatusBadge: View {
    let status: ProjectStatus

    var body: some View {
        Text(status.displayName)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(backgroundColor)
            )
            .foregroundColor(textColor)
    }

    // Blue = keeper (calm), gray = neutral default, amber/yellow = needs review.
    private var backgroundColor: Color {
        switch status {
        case .topShelf: .blue.opacity(0.12)
        case .collector: .gray.opacity(0.14)
        case .yardSale: .yellow.opacity(0.20)
        }
    }

    private var textColor: Color {
        switch status {
        case .topShelf: .blue
        case .collector: .secondary
        case .yardSale: .orange
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }

    struct FlowResult {
        var positions: [CGPoint] = []
        var size: CGSize = .zero

        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let s = subview.sizeThatFits(.unspecified)
                if x + s.width > width, x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                x += s.width + spacing
                lineHeight = max(lineHeight, s.height)
            }

            size = CGSize(width: width, height: y + lineHeight)
        }
    }
}
