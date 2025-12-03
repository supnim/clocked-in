//
//  AboutView.swift
//  clocked-in
//
//  Created by Nimesh on 03/12/2025.
//

import SwiftUI

struct AboutView: View {
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private var appIcon: NSImage {
        NSApp.applicationIconImage
    }

    var body: some View {
        VStack(spacing: 16) {
            // App Icon
            Image(nsImage: appIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 128, height: 128)
                .padding(.top, 20)

            // App Name
            Text("Clocked In")
                .font(.system(size: 24, weight: .bold))

            // Version
            Text("Version \(appVersion) (\(buildNumber))")
                .font(.system(size: 13))
                .foregroundColor(.secondary)


            Spacer()

            // Twitter/X Link
            Link(destination: URL(string: "https://x.com/sup_nim")!) {
                HStack(spacing: 4) {
                    Text("@sup_nim")
                }
                .font(.system(size: 12))
            }

            // Studio Link
            Link(destination: URL(string: "https://studio.gold")!) {
                Text("studio.gold")
                    .font(.system(size: 11))
            }
            .padding(.bottom, 16)
        }
        .frame(width: 300, height: 400)
    }
}

#Preview {
    AboutView()
}
