import AppKit
import XCTest
@testable import PokeTokenBar

@MainActor
final class PokemonLoadoutPickerTests: XCTestCase {
    func testCurrentSelectionAndEveryNativeMenuCandidateHaveLocalizedTooltips() throws {
        _ = NSApplication.shared
        let catalog = BattleTextCatalog.shared
        XCTAssertEqual(catalog.abilityDescriptions?.count, 164)
        for language in AppLanguage.allCases {
            let l = L(language)
            for (id, move) in catalog.moves {
                let text = catalog.moveTooltip(id, language: language)
                XCTAssertTrue(text.contains(catalog.description(id, language: language)), id)
                XCTAssertTrue(text.contains(l.battlePP + ": " + String(try XCTUnwrap(move.pp))), id)
                XCTAssertTrue(text.contains(l.battlePower + ": "), id)
                let type = try XCTUnwrap(move.type)
                XCTAssertEqual(catalog.moveMenuTitle(id, language: language),
                    catalog.moveName(id, language: language) + " · " + catalog.typeName(type, language: language) + " · " + l.battleCategory(try XCTUnwrap(move.category)))
                let scope=try XCTUnwrap(BattleTextCatalog.moveTargets[id],id)
                let target=l.battleMoveTarget(scope:scope,includesAllies:scope == "normal" || scope == "any")
                XCTAssertNotEqual(target,"—",id)
                XCTAssertTrue(text.contains(l.battleTarget + ": " + target),id)
                XCTAssertNotNil(move.accuracy, id)
                XCTAssertTrue(text.contains(l.battleBaseAccuracy + ": " + l.battleAccuracy(move.accuracy)), id)
            }
            for id in catalog.abilities.keys {
                XCTAssertNotEqual(catalog.abilityDescription(id, language: language), l.battleDescriptionUnavailable, id)
            }
            var selected: String?
            let coordinator = PokemonLoadoutPicker.Coordinator { selected = $0 }
            let button = NSPopUpButton(frame: .zero, pullsDown: true)
            let choices = [
                PokemonLoadoutChoice(id: "thunderbolt", title: catalog.moveMenuTitle("thunderbolt", language: language),
                    tooltip: catalog.moveTooltip("thunderbolt", language: language), selected: true),
                PokemonLoadoutChoice(id: "protect", title: catalog.moveMenuTitle("protect", language: language),
                    tooltip: catalog.moveTooltip("protect", language: language), enabled: false),
                PokemonLoadoutChoice(id: "adaptability", title: catalog.abilityName("adaptability", language: language),
                    tooltip: catalog.abilityTooltip("adaptability", language: language))
            ]
            PokemonLoadoutPicker.configure(button, title: choices[0].title, tooltip: choices[0].tooltip,
                choices: choices, target: coordinator, action: #selector(PokemonLoadoutPicker.Coordinator.select(_:)))
            XCTAssertEqual(button.toolTip, choices[0].tooltip)
            for (index, choice) in choices.enumerated() {
                let item = try XCTUnwrap(button.menu?.item(at: index + 1))
                XCTAssertEqual(item.title, choice.title)
                if let type = catalog.moves[BattleTextCatalog.key(choice.id)]?.type {
                    XCTAssertTrue(item.title.contains(catalog.typeName(type, language: language)), choice.id)
                }
                XCTAssertEqual(item.toolTip, choice.tooltip)
                XCTAssertEqual(item.isEnabled, choice.enabled)
                XCTAssertEqual(item.state, choice.selected ? .on : .off)
                coordinator.select(item)
                if choice.enabled { XCTAssertEqual(selected, choice.id) }
                else { XCTAssertNotEqual(selected, choice.id) }
            }
        }
    }
}
