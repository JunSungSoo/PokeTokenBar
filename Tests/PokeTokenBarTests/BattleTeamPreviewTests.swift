import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class BattleTeamPreviewTests: XCTestCase {
    func testBothSixMemberRostersRenderTogetherWithinTheLobbyInEveryLanguage() throws {
        func roster(_ prefix: String, _ ids: [Int]) -> [BattleRosterMember] {
            ids.enumerated().map { index, id in
                BattleRosterMember(BattlePokemon(id: prefix + String(index), speciesID: id, species: "", displayName: "", level: 50,
                    ability: "", nature: "hardy", gender: "", shiny: false, form: nil, ivs: [:], stats: [:], moves: []))
            }
        }
        let own = roster("a", [26,181,310,101,587,618]), foe = roster("b", [130,80,59,134,212,143])
        for language in AppLanguage.allCases {
            for mode in BattleMode.allCases {
                let view = BattleTeamPreview(own: own, opponent: foe, selected: Array(own.prefix(mode.battleSize)).map(\.id),
                    mode: mode, language: language, enabled: true, onSelect: { _ in })
                let image = try XCTUnwrap(ImageRenderer(content: view.frame(width: 320)).cgImage)
                XCTAssertLessThanOrEqual(image.height, 240, "Both rosters must be visible together: \(language) \(mode)")
                XCTAssertGreaterThan(image.height, 150)
                XCTAssertFalse(L(language).battleWaitingForRoster.isEmpty)
            }
        }
    }
}
