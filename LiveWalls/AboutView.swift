import SwiftUI
import AppKit

struct AboutView: View {
    private var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .aspectRatio(contentMode: .fit)

            Text(NSLocalizedString("about", comment: "About title"))
                .font(.title2)
                .fontWeight(.semibold)

            Text(String(format: NSLocalizedString("version_format", comment: "Version label"), shortVersion, buildNumber))
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Button {
                    InAppUpdater.shared.checkForUpdates()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text(NSLocalizedString("check_for_updates", comment: "Check for updates"))
                    }
                }
                .buttonStyle(.bordered)

                Button {
                    if let url = URL(string: "https://github.com/fparrav/LiveWalls") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "safari")
                        Text(NSLocalizedString("open_website", comment: "Open website"))
                    }
                }
                .buttonStyle(.bordered)
            }

            Spacer().frame(height: 4)

            Text("© 2024 LiveWalls")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(LiquidGlassMetrics.cardCornerRadius)
        .glassDarkSurface()
        .frame(width: 360)
    }
}

