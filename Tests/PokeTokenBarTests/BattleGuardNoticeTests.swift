import XCTest
@testable import PokeTokenBar

@MainActor final class BattleGuardNoticeTests:XCTestCase {
    func testRealProtectAndDetectBlocksReplayShieldOnDefenderInSinglesAndDoubles()throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let p=Process(),out=Pipe();p.executableURL=root.appendingPathComponent("BattleEngine/runtime/node")
        p.arguments=[root.appendingPathComponent("BattleEngine/tests/fixtures/guard-notices.cjs").path];p.standardOutput=out
        try p.run();let data=out.fileHandleForReading.readDataToEndOfFile();p.waitUntilExit();XCTAssertEqual(p.terminationStatus,0)
        let matches=try JSONDecoder().decode([String:[BattleFrame]].self,from:data)
        XCTAssertEqual(matches.count,4)
        for (key,frames) in matches {
            for (player,frame) in frames.enumerated() {
                let indices=frame.log.indices.filter{frame.log[$0].hasPrefix("|-activate|") && frame.log[$0].hasSuffix("|move: Protect")}
                XCTAssertEqual(indices.count,key.hasPrefix("doubles") ? 2:1)
                for i in indices {
                let id=(frame.logOffset ?? 0)+i
                for language in AppLanguage.allCases {
                    let presentation=BattlePresentationEvents(frame:frame,language:language,ownPlayer:player)
                    let guardEvent=try XCTUnwrap(presentation.events.first{$0.id==id})
                    XCTAssertEqual(guardEvent.phase,"guard");XCTAssertEqual(guardEvent.moveID,key.hasSuffix("detect") ? "detect":"protect")
                    XCTAssertEqual(guardEvent.source,BattleEffectPosition(own:player==1,slot:frame.log[i].contains("p2b:") ? 1:0))
                    XCTAssertTrue(guardEvent.targets.allSatisfy{$0.position==guardEvent.source && $0.hit})
                    XCTAssertNotNil(presentation.messages[id])
                    let attack=try XCTUnwrap(presentation.events.first{$0.moveID=="thunderbolt"})
                    XCTAssertLessThan(attack.id,guardEvent.id);XCTAssertFalse(attack.targets.isEmpty)
                    XCTAssertTrue(attack.targets.allSatisfy{!$0.hit})
                    let sound=try XCTUnwrap(PokeRogueOriginalCatalog.shared.entry(guardEvent)?.sounds)
                    XCTAssertTrue(sound.contains(key.hasSuffix("detect") ? "PRSFX- Detect.wav":"PRSFX- Protect.wav"))
                }
                }
            }
        }
    }
}
