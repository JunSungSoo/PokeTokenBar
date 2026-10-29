import XCTest
@testable import PokeTokenBar

@MainActor final class BattleStageModifierTests:XCTestCase {
    private func team(_ prefix:String,species:Int,name:String,ability:String,move:String,item:String?=nil)->[BattlePokemon] {
        let members=[(species,name,ability),(242,"Blissey","Natural Cure"),(26,"Raichu","Static"),(134,"Vaporeon","Water Absorb"),(212,"Scizor","Technician"),(80,"Slowbro","Own Tempo")]
        return members.enumerated().map {i,m in
            BattlePokemon(id:prefix+String(i),speciesID:m.0,species:m.1,displayName:m.1,level:100,
                ability:m.2,nature:"hardy",gender:"M",shiny:false,form:nil,
                ivs:["hp":17,"atk":17,"def":17,"spa":17,"spd":17,"spe":17],
                stats:["hp":1000,"atk":91,"def":300,"spa":96,"spd":300,"spe":107],
                moves:[i==0 ? move:"splash"],item:i==0 ? item:nil)
        }
    }
    func testActualModifiersReachNativeStagesAndLocalizedAbilityNoticesInBothFormats() async throws {
        for mode in [BattleMode.singles,.doubles] {
            for (id,name,ability,move,item,stat,expected) in [
                (398,"Staraptor","Intimidate","closecombat","staraptite","def",1),
                (497,"Serperior","Contrary","swordsdance","","atk",-2),
                (528,"Swoobat","Simple","calmmind","","spa",2)
            ] {
                let engine=BattleEngineProcess();var frames:[BattleFrame]=[]
                try engine.start(mode:mode,teams:[team("a",species:id,name:name,ability:ability,move:move,item:item.isEmpty ? nil:item),team("b",species:235,name:"Smeargle",ability:"Own Tempo",move:"splash")])
                engine.onFrames={frames=$0};engine.onFailure={XCTFail($0)};engine.onExit={XCTFail($0)}
                defer {engine.stop()}
                var deadline=Date().addingTimeInterval(6)
                while frames.isEmpty && Date()<deadline {try await Task.sleep(for:.milliseconds(20))}
                guard frames.count==2 else{XCTFail("Missing initial frames");continue}
                let oldTurn=frames[0].turn
                for player in 0...1 {
                    let f=frames[player]
                    let actions=f.slots.map {slot in
                        BattleAction(kind:"move",index:1,target:slot.moves[0].targetRequired ? (slot.moves[0].targets.first?.location ?? 0):0,
                            mega:player==0 && slot.slot==0 && id==398 ? true:nil)
                    }
                    try engine.choose(player:player,decision:.init(decisionID:f.decisionID,actions:actions,order:[]))
                }
                deadline=Date().addingTimeInterval(6)
                while frames[0].turn==oldTurn && Date()<deadline {try await Task.sleep(for:.milliseconds(20))}
                XCTAssertGreaterThan(frames[0].turn,oldTurn)
                XCTAssertEqual(frames[0].own[0].boosts?[stat],expected)
                if id==398 {XCTAssertEqual(frames[0].own[0].boosts?["spd"],1)}
                XCTAssertNil(frames[1].foe[0].boosts)
                let activeAbility=id==398 ? "Contrary":ability
                for language in AppLanguage.allCases {for player in 0...1 {
                    let presentation=BattlePresentationEvents(frame:frames[player],language:language,ownPlayer:player)
                    let text=presentation.messages.values.joined(separator:"\n")
                    XCTAssertTrue(text.contains(BattleTextCatalog.shared.abilityName(activeAbility,language:language)))
                    XCTAssertTrue(text.contains(L(language).battleStat(stat)))
                    XCTAssertTrue(text.contains(L(language).battleEvent(expected>0 ? "-boost":"-unboost")))
                }}
            }
        }
    }
}
