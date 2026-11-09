import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class BattleChoiceSummaryTests: XCTestCase {
    private func member(_ id: Int, active: Bool = true) -> BattleCombatant {
        .init(id: "\(id)", speciesID: id, name: "fixture", level: 100, shiny: false,
              active: active, form: nil, fainted: false, hp: 100, maxHP: 100, status: "", stats: nil)
    }
    private let ownPositions: Set<BattleEffectPosition> = [.init(own: true, slot: 0), .init(own: true, slot: 1)]
    private let foePositions: Set<BattleEffectPosition> = [.init(own: false, slot: 0), .init(own: false, slot: 1)]
    private func slot(_ scope: String, targeted: Bool = false, number: Int = 0) -> BattleSlot {
        .init(slot: number, mustSwitch: false, canPass: false, trapped: false, moves: [
            .init(index: 1, name: "Thunderbolt", apiName: "thunderbolt", pp: 10, maxPP: 15, disabled: false,
                  type: "Electric", power: 90, category: "Special", description: nil, matchups: [],
                  targetRequired: targeted, targets: targeted ? [.init(location: 2, name: "foe"), .init(location: -2, name: "ally")] : [], targetScope: scope)
        ])
    }
    private func summary(_ scope: String, target: Int = 0, number: Int = 0, language: AppLanguage = .ko) -> BattleChoiceSummary {
        .init(slot: slot(scope, targeted: target != 0, number: number), choice: .init(kind: "move", index: 1, target: target),
              own: [member(25), member(6), member(249, active: false)], foe: [member(151), member(130)], language: language)
    }
    func testIndependentSlotsAndExplicitAllyAndFoeTargets() {
        let first = summary("normal", target: 2), second = summary("adjacentAlly", target: -2, number: 1)
        XCTAssertEqual(first.positions, [.init(own: false, slot: 1)])
        XCTAssertEqual(second.positions, [.init(own: true, slot: 1)])
        XCTAssertTrue(first.target.contains(BattleTextCatalog.shared.speciesName(130, language: .ko)))
        XCTAssertTrue(second.target.contains(BattleTextCatalog.shared.speciesName(6, language: .ko)))
        XCTAssertNotEqual(first.target, second.target)
    }
    func testSpreadSelfAndAutomaticScopesDoNotInventTargets() {
        XCTAssertEqual(summary("allAdjacentFoes").positions, foePositions)
        XCTAssertEqual(summary("allAdjacent").positions, foePositions.union([.init(own: true, slot: 1)]))
        XCTAssertEqual(summary("all").positions, foePositions.union(ownPositions))
        XCTAssertEqual(summary("self", number: 1).positions, [.init(own: true, slot: 1)])
        XCTAssertEqual(summary("allySide").positions, ownPositions)
        XCTAssertTrue(summary("randomNormal").positions.isEmpty)
        XCTAssertTrue(summary("scripted").positions.isEmpty)
        XCTAssertEqual(summary("randomNormal").target, L(.ko).battleMoveTarget(scope: "randomNormal"))
    }
    func testPendingSwitchAndPassSummaries() {
        let own = [member(25), member(6), member(249, active: false)]
        let pending = BattleChoiceSummary(slot: slot("normal"), choice: nil, own: own, foe: [], language: .ko)
        XCTAssertEqual(pending.action, L(.ko).battleChoicePending)
        XCTAssertFalse(pending.chosen)
        let forcedSlot = BattleSlot(slot: 0, mustSwitch: true, canPass: false, trapped: false, moves: [])
        let forced = BattleChoiceSummary(slot: forcedSlot, choice: nil, own: own, foe: [], language: .ko)
        XCTAssertEqual(forced.action, L(.ko).battleSwitch)
        let swap = BattleChoiceSummary(slot: slot("normal"), choice: .init(kind: "switch", index: 3, target: 0), own: own, foe: [], language: .ko)
        XCTAssertEqual(swap.action, L(.ko).battleSwitch)
        XCTAssertTrue(swap.chosen)
        XCTAssertEqual(swap.target, BattleTextCatalog.shared.speciesName(249, language: .ko))
        XCTAssertTrue(swap.positions.isEmpty)
        let pass = BattleChoiceSummary(slot: slot("normal"), choice: .pass, own: own, foe: [], language: .ko)
        XCTAssertTrue(pass.positions.isEmpty)
        XCTAssertEqual(pass.action, L(.ko).battleChoicePass)
    }
    func testCardsKeepFixedSizeAcrossChoicesAndLanguagesOffscreen() throws {
        for language in AppLanguage.allCases {
            var sizes: [CGSize] = []
            for selected in [false, true] {
                for target in [2, -2, 0] {
                    let view = BattleChoiceSummaryView(name: BattleTextCatalog.shared.speciesName(25, language: language),
                        summary: summary(target == 0 ? "allAdjacentFoes" : "normal", target: target, language: language),
                        selected: selected, mega: selected, language: language).frame(width: 324)
                    let image = try XCTUnwrap(ImageRenderer(content: view).nsImage)
                    sizes.append(image.size)
                    XCTAssertEqual(image.size.width, 324)
                    XCTAssertLessThan(image.size.height, 85)
                }
            }
            XCTAssertTrue(sizes.allSatisfy { $0 == sizes[0] })
        }
    }
}
