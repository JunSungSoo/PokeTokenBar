import AppKit
import SwiftUI

/// Native menu item tooltips remain available while the selection menu is open.
/// SwiftUI Menu's label help alone only describes the closed control.
struct PokemonLoadoutChoice: Equatable {
    let id: String
    let title: String
    let tooltip: String
    var selected = false
    var enabled = true
}

@MainActor
struct PokemonLoadoutPicker: NSViewRepresentable {
    let title: String
    let tooltip: String
    let choices: [PokemonLoadoutChoice]
    let onSelect: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }
    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.controlSize = .small
        button.font = .systemFont(ofSize: 13)
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return button
    }
    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.onSelect = onSelect
        Self.configure(button, title: title, tooltip: tooltip, choices: choices,
                       target: context.coordinator, action: #selector(Coordinator.select(_:)))
    }
    static func configure(_ button: NSPopUpButton, title: String, tooltip: String,
                          choices: [PokemonLoadoutChoice], target: AnyObject, action: Selector) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        for choice in choices {
            let item = NSMenuItem(title: choice.title, action: action, keyEquivalent: "")
            item.target = target
            item.representedObject = choice.id
            item.toolTip = choice.tooltip
            item.state = choice.selected ? .on : .off
            item.isEnabled = choice.enabled
            menu.addItem(item)
        }
        button.menu = menu
        button.toolTip = tooltip
        button.isEnabled = !choices.isEmpty
        button.setAccessibilityLabel(title)
        button.setAccessibilityHelp(tooltip)
    }
    final class Coordinator: NSObject {
        var onSelect: (String) -> Void
        init(onSelect: @escaping (String) -> Void) { self.onSelect = onSelect }
        @objc func select(_ sender: NSMenuItem) {
            guard sender.isEnabled, let id = sender.representedObject as? String else { return }
            onSelect(id)
        }
    }
}
