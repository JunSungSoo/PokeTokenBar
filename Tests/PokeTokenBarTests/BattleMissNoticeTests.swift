import XCTest
@testable import PokeTokenBar

@MainActor
final class BattleMissNoticeTests: XCTestCase {
    func testRealAccuracyMissAppearsInSinglesAndDoublesForBothPlayersInEveryLanguage() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let process = Process(), output = Pipe(), errors = Pipe()
        process.executableURL = root.appendingPathComponent("BattleEngine/runtime/node")
        process.arguments = [root.appendingPathComponent("BattleEngine/tests/fixtures/miss-notices.cjs").path]
        process.standardOutput = output; process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        let matches = try JSONDecoder().decode([String: [BattleFrame]].self, from: data)
        XCTAssertEqual(Set(matches.keys), ["singles", "doubles"])
        for frames in matches.values {
            for (player, frame) in frames.enumerated() {
                let index = try XCTUnwrap(frame.log.firstIndex { $0.hasPrefix("|-miss|") })
                let id = (frame.logOffset ?? 0) + index
                for language in AppLanguage.allCases {
                    let presentation = BattlePresentationEvents(frame: frame, language: language, ownPlayer: player)
                    let l = L(language), catalog = BattleTextCatalog.shared
                    let pokemon = l.battleSide(ally: player == 0) + " " + catalog.pokemonName("Pikachu", language: language)
                    let text = try XCTUnwrap(presentation.messages[id])
                    XCTAssertEqual(text, l.battleMoveMissed(pokemon, move: catalog.moveName("Thunderbolt", language: language)))
                    XCTAssertEqual(presentation.events.first { $0.id == id }?.phase, "transition")
                    let move = try XCTUnwrap(presentation.events.last { $0.id < id && BattleTextCatalog.key($0.move) == "thunderbolt" })
                    XCTAssertFalse(move.targets.isEmpty)
                    XCTAssertTrue(move.targets.allSatisfy { !$0.hit }, "A miss notice must not create a successful hit")
                }
            }
        }
    }

    func testUsesActualLatestMoveAndDoesNotInventMissingContext() {
        let attack = "|move|p1a: Pikachu|Ice Beam|p2a: Raichu|[miss]"
        let miss = "|-miss|p1a: Pikachu|p2a: Raichu"
        let lines = ["|turn|1", attack, "", "|-message|interleaved event", miss]
        XCTAssertTrue(BattleLogText.describeMiss(lines, at: 4, language: .ko, ownPlayer: 0)?.contains("냉동빔은 맞지 않았다.") == true)
        for log in [[miss], [attack, "|turn|2", miss], [attack, "|move|p2a: Raichu|Splash|p2a: Raichu", miss], [attack, "|-immune|p2a: Raichu"]] {
            XCTAssertNil(BattleLogText.describeMiss(log, at: log.count - 1, language: .ko, ownPlayer: 0))
        }
        let enemy = ["|move|p2b: Raichu|Ice Beam|p1a: Pikachu|[miss]", "|-miss|p2b: Raichu|p1a: Pikachu"]
        let expected = L(.ko).battleSide(ally: false) + " 라이츄의 냉동빔은 맞지 않았다."
        XCTAssertEqual(BattleLogText.describeMiss(enemy, at: 1, language: .ko, ownPlayer: 0), expected)
        XCTAssertNil(BattleLogText.describeMiss(lines, at: -1, language: .ko, ownPlayer: 0))
    }

    func testKoreanMoveParticleMatchesFinalConsonant() {
        XCTAssertEqual(L(.ko).battleMoveMissed("피카츄", move: "10만볼트"), "피카츄의 10만볼트는 맞지 않았다.")
        XCTAssertEqual(L(.ko).battleMoveMissed("피카츄", move: "냉동빔"), "피카츄의 냉동빔은 맞지 않았다.")
        XCTAssertEqual(KoreanParticle.topic.attach(to: "Thunderbolt"), "Thunderbolt은(는)")
    }
}
