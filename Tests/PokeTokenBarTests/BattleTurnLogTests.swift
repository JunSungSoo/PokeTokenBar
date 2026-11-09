import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class BattleTurnLogTests: XCTestCase {
    private func frame(_ log:[String],offset:Int=0,scenes:[BattleScene]?=nil)->BattleFrame {
        .init(revision:"test",turn:3,decisionID:"3:move",preview:false,waiting:false,own:[],foe:[],slots:[],log:log,logOffset:offset,scenes:scenes,ended:false,winner:nil)
    }
    func testIncrementalFramesDoNotDuplicateAndKeepRepeatedActions() {
        var model=BattleTurnLog()
        let first=["|turn|1","|move|p1a: Pikachu|Thunderbolt|p2a: Mew"]
        model.receive(frame(first));model.receive(frame(first))
        model.receive(frame(first+["|turn|2",first[1]]))
        let groups=model.groups(language:.ko,ownPlayer:0)
        XCTAssertEqual(groups.map(\.turn),[1,2])
        XCTAssertEqual(groups.map{ $0.entries.count },[1,1])
        XCTAssertEqual(model.records.count,4)
        XCTAssertNotEqual(groups[0].entries[0].id,groups[1].entries[0].id)
    }
    func testLogWindowRollsForwardWithoutLosingEarlierTurnsAndResetsForNewBattle() {
        var model=BattleTurnLog()
        model.receive(frame(["|turn|1","|move|p1a: Pikachu|Thunderbolt|p2a: Mew"]))
        model.receive(frame(["|turn|2","|move|p2a: Mew|Psychic|p1a: Pikachu"],offset:2))
        XCTAssertEqual(model.groups(language:.ko,ownPlayer:0).map(\.turn),[1,2])
        model.receive(frame(["|turn|1","|move|p1a: Mew|Recover|p1a: Mew"]))
        XCTAssertEqual(model.records.count,2)
        XCTAssertEqual(model.groups(language:.ko,ownPlayer:0).map(\.turn),[1])
        XCTAssertTrue(model.groups(language:.ko,ownPlayer:0)[0].entries[0].text.contains(BattleTextCatalog.shared.moveName("recover",language:.ko)))
    }
    func testSameLengthNewBattleReplacesOverlappingRecords() {
        var model=BattleTurnLog()
        model.receive(frame(["|turn|1","|move|p1a: Pikachu|Thunderbolt|p2a: Mew"]))
        model.receive(frame(["|turn|1","|move|p1a: Pikachu|Protect|p1a: Pikachu"]))
        XCTAssertEqual(model.records.count,2)
        XCTAssertTrue(model.groups(language:.en,ownPlayer:0)[0].entries[0].text.contains("Protect"))
    }
    func testTruncatedReconnectDoesNotInventATurnAndHistoryIsBounded() {
        var model=BattleTurnLog()
        model.receive(frame(["|move|p1a: Pikachu|Thunderbolt|p2a: Mew","|turn|7"],offset:200))
        XCTAssertNil(model.groups(language:.en,ownPlayer:0).first?.turn)
        for batch in 0..<11 {
            model.receive(frame((0..<100).map{ "|turn|\(batch*100+$0+8)" },offset:202+batch*100))
        }
        XCTAssertEqual(model.records.count,BattleTurnLog.capacity)
        XCTAssertEqual(model.records.last?.turn,1107)
    }
    func testMissStatusAbilityAndPerspectiveTranslateFromPublicRecords() {
        var model=BattleTurnLog()
        model.receive(frame(["|turn|1","|move|p1a: Pikachu|Thunderbolt|p2a: Mew","|-miss|p1a: Pikachu|p2a: Mew",
                             "|-status|p2a: Mew|par","|-ability|p1a: Pikachu|Static","|turn|2",
                             "|-weather|RainDance|[upkeep]","|cant|p2a: Mew|par","|faint|p2a: Mew"]))
        for language in AppLanguage.allCases {
            let l=L(language)
            let groups=model.groups(language:language,ownPlayer:0)
            let text=groups.flatMap(\.entries).map(\.text).joined(separator:"\n")
            XCTAssertTrue(text.contains(BattleTextCatalog.shared.moveName("thunderbolt",language:language)))
            XCTAssertTrue(text.contains(l.battleStatus("par")))
            XCTAssertTrue(text.contains(BattleTextCatalog.shared.abilityName("static",language:language)))
            XCTAssertEqual(groups[0].entries.count,4)
            XCTAssertEqual(groups[1].entries.count,2)
            XCTAssertTrue(text.contains(l.battleMoveMissed(l.battleSide(ally:true)+" "+BattleTextCatalog.shared.pokemonName("p1a: Pikachu",language:language),move:BattleTextCatalog.shared.moveName("thunderbolt",language:language))))
            XCTAssertNotEqual(text,model.groups(language:language,ownPlayer:1).flatMap(\.entries).map(\.text).joined(separator:"\n"))
        }
    }
    func testOpeningSwitchesKeepTheirSideAndEmptyPanelTranslates() {
        var model=BattleTurnLog()
        model.receive(frame(["|switch|p1a: Raichu|Raichu, L37|143/143","|switch|p2a: Raichu|Raichu, L37|100/100"]))
        for language in AppLanguage.allCases {
            let l=L(language),groups=model.groups(language:language,ownPlayer:0)
            XCTAssertEqual(groups.count,1)
            XCTAssertEqual(groups[0].turn,0)
            XCTAssertTrue(groups[0].entries[0].text.hasPrefix(l.battleSide(ally:true)))
            XCTAssertTrue(groups[0].entries[1].text.hasPrefix(l.battleSide(ally:false)))
            XCTAssertFalse(l.battleTurnLogEmpty.isEmpty)
            XCTAssertNotEqual(l.battleTurnLogState(true),l.battleTurnLogState(false))
            XCTAssertNotEqual(l.battleLogTurn(nil),l.battleLogTurn(0))
        }
        XCTAssertTrue(BattleTurnLog().groups(language:.ko,ownPlayer:0).isEmpty)
    }
    func testPendingAnimationCannotRevealAuthoritativeNextTurnInLog() throws {
        let playback=BattleScenePlayback()
        let previous=frame(["|turn|1"])
        let scene=BattleScene(id:40,turn:2,own:[],foe:[],field:.init(weather:"",weatherSuppressed:false,conditions:[],ownSide:[],foeSide:[]))
        let next=frame(["|turn|1","|move|p2a: Mew|Psychic|p1a: Pikachu","|turn|2"],scenes:[scene])
        playback.accept(previous);playback.accept(next)
        XCTAssertTrue(playback.pending)
        var model=BattleTurnLog();model.receive(try XCTUnwrap(playback.frame))
        XCTAssertTrue(model.groups(language:.ko,ownPlayer:0).isEmpty)
        playback.apply(scene);model.receive(try XCTUnwrap(playback.frame))
        XCTAssertTrue(model.groups(language:.ko,ownPlayer:0).isEmpty)
        playback.finish();model.receive(try XCTUnwrap(playback.frame))
        XCTAssertEqual(model.groups(language:.ko,ownPlayer:0).flatMap(\.entries).count,1)
    }
    func testPanelStartsCollapsedAndExpansionHasBoundedHeightInEveryLanguage() throws {
        var model=BattleTurnLog();model.receive(frame(["|turn|1","|move|p1a: Pikachu|Thunderbolt|p2a: Mew"]))
        for language in AppLanguage.allCases {
            let collapsed=try XCTUnwrap(ImageRenderer(content:BattleTurnLogView(log:model,language:language,ownPlayer:0,expanded:.constant(false)).frame(width:636)).nsImage)
            let expanded=try XCTUnwrap(ImageRenderer(content:BattleTurnLogView(log:model,language:language,ownPlayer:0,expanded:.constant(true)).frame(width:636)).nsImage)
            XCTAssertEqual(expanded.size.width,collapsed.size.width)
            XCTAssertEqual(expanded.size.height-collapsed.size.height,126,accuracy:1)
        }
    }
}
