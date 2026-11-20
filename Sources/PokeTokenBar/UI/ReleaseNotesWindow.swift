import AppKit
import SwiftUI

/// A standalone window, so the notes stay open after the menu-bar popover closes.
@MainActor
final class ReleaseNotesWindowController: NSObject, NSWindowDelegate {
    static let shared = ReleaseNotesWindowController()
    static let title = "Release Note"
    private(set) var window: NSWindow?

    func show() {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = Self.title
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: ReleaseNotesView(entries: ReleaseHistory.bundled))
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() { window?.close() }

    func windowWillClose(_ notification: Notification) { window = nil }
}

@MainActor
struct ReleaseNotesView: View {
    let entries: [ReleaseHistory.Entry]
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.title).font(.headline)
                        ForEach(Array(entry.changes.enumerated()), id: \.offset) { _, change in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("•").foregroundStyle(.secondary)
                                Text(change).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .textSelection(.enabled)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .reservesScrollerLane()
        }
        .frame(minWidth: 420, minHeight: 360)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
