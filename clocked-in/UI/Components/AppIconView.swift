import SwiftUI

struct AppIconView: View {
    let iconData: Data?
    let size: CGSize

    init(iconData: Data?, size: CGSize = CGSize(width: 16, height: 16)) {
        self.iconData = iconData
        self.size = size
    }

    var body: some View {
        Group {
            if let iconData = iconData,
               let nsImage = NSImage(data: iconData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height)
            } else {
                // Fallback: generic app icon
                Image(systemName: "app.dashed")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height)
                    .foregroundColor(.secondary)
            }
        }
    }
}