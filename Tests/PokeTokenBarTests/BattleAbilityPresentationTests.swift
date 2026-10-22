import XCTest
@testable import PokeTokenBar

final class BattleAbilityPresentationTests: XCTestCase {
    func testIntimidateAndMoxieAttributeActualStageChangesInEveryLanguage() {
        for language in AppLanguage.allCases {
            for (ability, effect, pokemon) in [("Intimidate", "-unboost", "p2a: Pikachu"), ("Moxie", "-boost", "p1a: Gyarados")] {
                let messages = BattleLogText.abilityChanges(["|-ability|p1a: Gyarados|\(ability)|boost", "|\(effect)|\(pokemon)|atk|1"], language: language)
                XCTAssertEqual(messages.count, 2)
                XCTAssertTrue(messages.last!.contains(BattleTextCatalog.shared.abilityName(ability, language: language)))
                XCTAssertTrue(messages.last!.contains(L(language).battleStat("atk")))
                XCTAssertTrue(messages.last!.contains(L(language).battleEvent(effect)))
            }
        }
    }
    func testBlockingOneDoublesTargetDoesNotLoseTheOtherTargetsSourceAndPerspective() {
        let log = ["|-ability|p1a: Gyarados|Intimidate|boost", "|-fail|p2a: Tentacool|unboost|[from] ability: Clear Body", "|-unboost|p2b: Raichu|atk|1"]
        let host = BattleLogText.abilityChanges(log, language: .ko, ownPlayer: 0)
        let guest = BattleLogText.abilityChanges(log, language: .ko, ownPlayer: 1)
        XCTAssertTrue(host.last!.contains("아군 갸라도스 · 위협 → 상대 라이츄"))
        XCTAssertTrue(guest.last!.contains("상대 갸라도스 · 위협 → 아군 라이츄"))
    }
    func testDefiantReactionDoesNotStealIntimidatesSecondTarget() {
        let log = ["|-ability|p1a: Gyarados|Intimidate|boost", "|-unboost|p2a: Bisharp|atk|1", "|-ability|p2a: Bisharp|Defiant|boost", "|-boost|p2a: Bisharp|atk|2", "|-unboost|p2b: Raichu|atk|1"]
        let messages = BattleLogText.abilityChanges(log, language: .en)
        XCTAssertTrue(messages.contains { $0.contains("Defiant → Opponent Bisharp") })
        XCTAssertTrue(messages.last?.contains("Intimidate → Opponent Raichu") == true)
        XCTAssertFalse(messages.last?.contains("Defiant") == true)
    }
    func testCopyTransformationAndUncommonAbilityEventsRemainVisible() {
        let messages = BattleLogText.abilityChanges([
            "|-ability|p1a: Porygon2|Intimidate|[from] ability: Trace|[of] p2a: Gyarados",
            "|-transform|p1a: Ditto|p2a: Pikachu|[from] ability: Imposter",
            "|-heal|p1a: Slowpoke|120/143|[from] ability: Regenerator",
            "|-weather|RainDance|[from] ability: Drizzle|[of] p2a: Politoed",
            "|-end|p1a: Zoroark|Illusion"], language: .en)
        XCTAssertEqual(messages.count, 5)
        XCTAssertTrue(messages.contains { $0.contains("Trace") && $0.contains("Intimidate") })
        XCTAssertTrue(messages.contains { $0.contains("Imposter") })
        XCTAssertTrue(messages.contains { $0.contains("Illusion") && $0.contains("Effect ended") })
        XCTAssertTrue(messages.contains { $0.contains("Regenerator") && $0.contains("HP restored") })
        XCTAssertTrue(messages.contains { $0.contains("Drizzle") && $0.contains("Rain") })
        XCTAssertTrue(BattleLogText.describe("|-end|p1a: Zoroark|Illusion", language: .en)?.contains("Illusion") == true)
    }
    func testAbilityCausesAndBlockingEffectsAreLocalizedWithoutAttributingNextMove() {
        let events = ["|-ability|p1a: Gyarados|Intimidate|boost", "|-unboost|p2a: Pikachu|atk|1", "|move|p2a: Pikachu|Growl|p1a: Gyarados", "|-unboost|p1a: Gyarados|atk|1", "|-status|p2a: Pikachu|par|[from] ability: Static|[of] p1a: Pichu", "|-immune|p2a: Tentacool|[from] ability: Clear Body", "|-activate|p2a: Pikachu|ability: Lightning Rod"]
        let messages = BattleLogText.abilityChanges(events, language: .ko)
        XCTAssertEqual(messages.count, 5)
        let text = messages.joined(separator: "\n")
        XCTAssertTrue(text.contains("정전기"))
        XCTAssertTrue(text.contains("마비"))
        XCTAssertTrue(text.contains("클리어바디"))
        XCTAssertTrue(text.contains("피뢰침"))
        XCTAssertTrue(BattleLogText.abilityChanges(["|move|p1a: Pikachu|Thunderbolt|p2a: Eevee"], language: .ko).isEmpty)
    }
}
