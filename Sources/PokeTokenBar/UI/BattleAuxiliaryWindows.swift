import AppKit
import SwiftUI
import Observation

@MainActor @Observable
final class BattleAuxiliaryState {
    var fieldVisible = true
    var statsVisible = true
}

enum BattleAuxiliaryKind { case field, stats }

/// Frames use the visible screen, including title bars, so controls stay above the Dock.
struct BattleWindowLayout {
    static func preferredWidth(for mode: BattleMode) -> CGFloat { mode == .doubles ? 680 : 660 }
    let main: NSRect
    let field: NSRect
    let stats: NSRect
    init(screen: NSRect, mode: BattleMode, main existingMain: NSRect? = nil) {
        let gap: CGFloat = 10
        let width = min(Self.preferredWidth(for: mode), screen.width)
        let height = min(700, screen.height)
        main = existingMain ?? NSRect(x: screen.midX - width / 2, y: screen.midY - height / 2, width: width, height: height)
        let anchor = main
        let panelWidth = min(screen.width, min(250, max(200, (screen.width - anchor.width - 2 * gap) / 2)))
        func panel(left: Bool, height: CGFloat) -> NSRect {
            let x = left ? anchor.minX - gap - panelWidth : anchor.maxX + gap
            return NSRect(x: min(max(x, screen.minX), screen.maxX - panelWidth),
                y: max(screen.minY, anchor.maxY - min(height, screen.height)),
                width: panelWidth, height: min(height, screen.height))
        }
        field = panel(left: true, height: 400)
        stats = panel(left: false, height: 640)
    }

}

@MainActor
struct BattleAuxiliaryView: View {
    let kind: BattleAuxiliaryKind
    let battle: BattleCoordinator
    let store: CompanionStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let frame = battle.presentation.frame ?? battle.frame {
                    if kind == .field {
                        if let field = frame.field, !field.isEmpty {
                            BattleFieldStatus(field: field, language: store.language)
                        } else {
                            Text(store.l.battleNoFieldEffects).foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(frame.own.filter(\.active)) { pokemon in
                            BattleOwnStats(pokemon: pokemon, language: store.language)
                        }

                    }
                } else { ProgressView(store.l.battlePreparing) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(12).reservesScrollerLane()
        }.environment(\.locale, store.language.displayLocale)
    }
}
