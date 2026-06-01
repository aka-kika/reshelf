import SwiftUI
import AppKit

struct ReshelfBrandHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let nsImage = ReshelfBrandImage.nsImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .interpolation(.high)
                } else {
                    Image(systemName: "books.vertical.fill")
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .aspectRatio(contentMode: .fit)
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text("reshelf")
                    .font(.system(size: 15, weight: .semibold))
                Text("repo shelf")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("reshelf")
    }
}
