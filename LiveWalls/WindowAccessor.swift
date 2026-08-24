import SwiftUI
import AppKit

/// Bridges to the hosting `NSWindow` of a SwiftUI `WindowGroup` scene so its
/// AppKit-only properties (title bar transparency, movable-by-background,
/// etc.) can be configured from SwiftUI, mirroring how `DesktopVideoWindowMejorada`
/// configures its own `NSWindow` properties directly.
///
/// Usage: attach as an invisible background view so it can resolve `view.window`.
/// ```swift
/// content
///     .background(WindowAccessor { window in
///         window.titlebarAppearsTransparent = true
///         window.titleVisibility = .hidden
///     })
/// ```
struct WindowAccessor: NSViewRepresentable {
    var configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                configure(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                configure(window)
            }
        }
    }
}
