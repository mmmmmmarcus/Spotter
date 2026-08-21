import AppKit
import SwiftUI

/// Installs SwiftUI content into a fixed-frame borderless panel as a plain subview, never as the
/// window's `contentView`. An `NSHostingView` that *is* the content view runs AppKit's
/// window content-size extrema update inside the window's constraint pass, and when the view graph
/// invalidates its transform right there — an animation mid-flight during a display-cycle flush —
/// macOS 26 throws and `NSApplication` crashes on the exception (both 1.5.2 crash reports). A
/// subview hosting view never drives window sizing, so that path cannot start.
@MainActor
enum PanelHosting {
    /// The panel's frame stays the caller's to set; the container just relays it to the host.
    static func install<Content: View>(_ host: NSHostingView<Content>, in panel: NSPanel) {
        host.sizingOptions = []
        let container = NSView()
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        host.frame = container.bounds
        container.addSubview(host)
        panel.contentView = container
    }
}
