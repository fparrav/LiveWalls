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
        .frame(width: 360, height: 420)
        .glassDarkSurface()
        // With `fullSizeContentView`, SwiftUI still reserves a titlebar-height
        // safe-area inset by default; without ignoring it here the glass card
        // renders below a bare strip instead of flush with the window's top
        // edge, defeating "the window itself is the glass surface".
        .ignoresSafeArea()
        // Task 7.1: the window itself is the glass surface -- no inner card
        // floating inside a plain system frame. The title bar is hidden and
        // the window made transparent/movable-by-background so only the
        // rounded, bordered `glassDarkSurface()` shape is visible, with a
        // single native close control remaining in the (invisible) title bar.
        .background(WindowAccessor { window in
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.styleMask.remove(.resizable)
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            // macOS computes the window shadow from the frame at the time
            // `isOpaque`/`backgroundColor` change; without forcing a
            // recompute here the shadow keeps the shape of the window's
            // original opaque rect (titlebar included), rendering as a
            // mismatched rectangular shadow behind the rounded glass card.
            window.invalidateShadow()
        })
    }
}

