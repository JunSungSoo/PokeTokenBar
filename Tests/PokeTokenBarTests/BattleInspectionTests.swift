import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class BattleInspectionTests: XCTestCase {
    private func move(_ name: String) -> BattleMove {
        BattleMove(index: 1, name: name, apiName: name, pp: 5, maxPP: 10, disabled: false,
                   type: "Normal", power: 50, category: "Physical", description: nil, matchups: [],
                   targetRequired: false, targets: [])
    }
    private var pokemon: BattleCombatant {
        BattleCombatant(id: "own", speciesID: 130, name: "Gyarados", level: 50, shiny: false,
                        active: true, form: nil, fainted: false, hp: 75, maxHP: 150, status: "par",
                        stats: nil, item: "leftovers", effects: ["taunt", "confusion", "substitute"])
    }
    func testCurseDescriptionAndTypelessMoveUseLiveContextInEveryLanguage() {
        var curse = move("curse"), struggle = move("struggle")
        struggle.ignoresTypeMatchup = true
        for language in AppLanguage.allCases {
            let l = L(language)
            curse.targetScope = "self"
            let ownDescription = l.battleMoveDescription(curse)
            curse.targetScope = "normal"
            XCTAssertNotEqual(l.battleMoveDescription(curse), ownDescription)
            XCTAssertNotEqual(l.battleMoveType(struggle), BattleTextCatalog.shared.typeName("Normal", language: language))
            XCTAssertFalse(l.battleTypelessMove.isEmpty)
            curse.targetScope = nil
            XCTAssertEqual(l.battleMoveDescription(curse), BattleTextCatalog.shared.description("curse", language: language))
        }
    }
    func testDisabledReasonsAndSwitchInformationAreLocalized() {
        var disabled = move("recover")
        disabled = BattleMove(index: 1, name: disabled.name, apiName: disabled.apiName,
                              pp: 5, maxPP: 10, disabled: true, type: disabled.type, power: 0,
                              category: "Status", description: nil, matchups: [], targetRequired: false,
                              targets: [], disableReason: "taunt")
        for language in AppLanguage.allCases {
            let l = L(language), text = l.battleSwitchSummary(pokemon)
            XCTAssertTrue(text.contains("75/150"))
            XCTAssertTrue(text.contains(l.battleStatus("par")))
            XCTAssertTrue(text.contains(BattleHeldItems.item("leftovers")!.name(language)))
            XCTAssertTrue(l.battleDisabledReason(disabled)!.contains(BattleTextCatalog.shared.moveName("taunt", language: language)))
            XCTAssertEqual(l.battleActiveEffect("confusion"), l.battleStatus("confusion"))
        }
    }
    func testOngoingEffectsRenderAndOldCombatantsDecodeWithoutThem() throws {
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(pokemon)) as? [String: Any])
        old.removeValue(forKey: "effects")
        let legacy = try decoder.decode(BattleCombatant.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(legacy.effects)
        let current = try decoder.decode(BattleCombatant.self, from: encoder.encode(pokemon))
        XCTAssertEqual(current.effects, pokemon.effects)
        let normal = try XCTUnwrap(ImageRenderer(content: BattleOwnStats(pokemon: legacy, language: .ko).frame(width: 260)).nsImage)
        let affected = try XCTUnwrap(ImageRenderer(content: BattleOwnStats(pokemon: current, language: .ko).frame(width: 260)).nsImage)
        XCTAssertGreaterThan(affected.size.height, normal.size.height)
    }
}
