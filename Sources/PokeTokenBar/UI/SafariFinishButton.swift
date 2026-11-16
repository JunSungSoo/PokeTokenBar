import AppKit
import SwiftUI

/// Native target/action gives Finish a direct, keyboard-accessible exit path.
@MainActor
struct SafariFinishButton: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let enabled: Bool
    var identifier = "safari-finish"
    let action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action:action) }
    func makeNSView(context:Context) -> NSButton {
        let button = NSButton(title:title,target:context.coordinator,action:#selector(Coordinator.finish))
        button.bezelStyle = .rounded
        button.setAccessibilityIdentifier(identifier)
        return button
    }
    func updateNSView(_ button:NSButton,context:Context) {
        context.coordinator.action = action
        button.title = title; button.isEnabled = enabled && isEnabled
        button.setAccessibilityLabel(title)
    }
    func sizeThatFits(_ proposal:ProposedViewSize,nsView:NSButton,context:Context) -> CGSize? { nsView.fittingSize }
    @MainActor final class Coordinator:NSObject {
        var action:() -> Void
        init(action:@escaping () -> Void) { self.action = action }
        @objc func finish() { action() }
    }
}
