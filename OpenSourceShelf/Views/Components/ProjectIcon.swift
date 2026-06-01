import SwiftUI

struct ProjectIcon: View {
    let project: ToolProject
    var size: CGFloat = 28

    var body: some View {
        if let data = project.iconData, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.18)
                    .fill(Color.blue.opacity(0.08))
                    .frame(width: size, height: size)
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
        }
    }
}
