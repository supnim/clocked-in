import SwiftUI

struct AppIconView: View {
    let iconData: Data?
    let size: CGSize

    let appName: String?

    init(iconData: Data?, size: CGSize = CGSize(width: 16, height: 16), appName: String? = nil) {
        self.iconData = iconData
        self.size = size
        self.appName = appName
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
        .accessibilityLabel(appName.map { "\($0) icon" } ?? "App icon")
    }
}