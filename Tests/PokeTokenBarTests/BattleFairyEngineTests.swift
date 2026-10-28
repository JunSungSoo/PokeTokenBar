import XCTest
@testable import PokeTokenBar

@MainActor final class BattleFairyEngineTests:XCTestCase {
    private func team(_ prefix:String,move:String)->[BattlePokemon] {
        zip([235,242,26,134,80,212],["Smeargle","Blissey","Raichu","Vaporeon","Slowbro","Scizor"]).enumerated().map {i,s in
            BattlePokemon(id:prefix+String(i),speciesID:s.0,species:s.1,displayName:s.1,level:50,
                ability:["Own Tempo","Natural Cure","Static","Water Absorb","Oblivious","Swarm"][i],nature:"Hardy",gender:"M",shiny:false,form:nil,
                ivs:["hp":31,"atk":31,"def":31,"spa":31,"spd":31,"spe":31],
                stats:["hp":500,"atk":120,"def":150,"spa":120,"spd":150,"spe":100],moves:[i==0 ? move:"splash"])
        }
    }
    func testNativePreflightAcceptsOnlyTheRequestedFutureMoveException() async throws {
        let allowed=["aromaticmist","babydolleyes","craftyshield","dazzlinggleam","disarmingvoice","drainingkiss","fairylock","fairywind","flowershield","geomancy","lightofruin","mistyterrain","moonblast","playrough"]
        for move in allowed {
            let abilities=try await BattleEngineProcess.validate(mode:.singles,team:team("a",move:move))
            XCTAssertEqual(abilities.count,6,move)
        }
        for move in ["mysticalfire","flowertrick","fleurcannon","spiritbreak","alluringvoice"] {
            do { _ = try await BattleEngineProcess.validate(mode:.singles,team:team("a",move:move));XCTFail("Unexpectedly accepted \(move)") }
            catch {XCTAssertTrue(error.localizedDescription.contains("Unsupported move"),String(describing:error))}
        }
    }
    func testNewEngineRevisionAndFairyMoveDetailsReachNativeFrames() async throws {
        let engine=BattleEngineProcess()
        var delivered=false
        try engine.start(mode:.singles,teams:[team("a",move:"moonblast"),team("b",move:"splash")])
        engine.onFailure={reason in XCTFail(reason)}
        engine.onExit={reason in XCTFail(reason)}
        engine.onFrames={frames in
            guard !delivered else{return};delivered=true
            XCTAssertTrue(frames.allSatisfy{$0.revision==BattleEngineProcess.revision})
            XCTAssertEqual(frames[0].slots.first?.moves.first?.apiName,"moonblast")

        }
        defer {engine.stop()}
        let deadline=Date().addingTimeInterval(6)
        while !delivered && Date()<deadline {try await Task.sleep(for:.milliseconds(20))}
        XCTAssertTrue(delivered,"A Fairy frame must decode through the production process adapter")
    }
    func testActualFairyActionsBecomeLocalizedOriginalEffectsAndGlobalFieldEvents() async throws {
        for mode in [BattleMode.singles,.doubles] {
            for move in PokemonFairyMoves.shared.moves.keys.sorted() {
                let engine=BattleEngineProcess()
                var frames:[BattleFrame]=[]
                try engine.start(mode:mode,teams:[team("a",move:move),team("b",move:"splash")])
                engine.onFrames={frames=$0}
                engine.onFailure={XCTFail($0)}
                engine.onExit={XCTFail($0)}
                defer {engine.stop()}
                var end=Date().addingTimeInterval(6)
                while frames.isEmpty && Date()<end {try await Task.sleep(for:.milliseconds(20))}
                XCTAssertEqual(frames.count,2)
                guard frames.count==2 else{continue}
                let turn=frames[0].turn
                for player in 0...1 {
                    let f=frames[player]
                    let actions=f.slots.map {slot -> BattleAction in
                        if slot.canPass {return .pass}
                        let m=slot.moves[0]
                        return .init(kind:"move",index:m.index,target:m.targetRequired ? (m.targets.first?.location ?? 0):0)
                    }
                    try engine.choose(player:player,decision:.init(decisionID:f.decisionID,actions:actions,order:[]))
                }
                end=Date().addingTimeInterval(6)
                while frames[0].turn==turn && Date()<end {try await Task.sleep(for:.milliseconds(20))}
                XCTAssertGreaterThan(frames[0].turn,turn)
                let presentation=BattlePresentationEvents(frame:frames[0],language:.ko,ownPlayer:0)
                let matching=presentation.events.filter{BattleTextCatalog.key($0.moveID ?? "")==move}
                XCTAssertEqual(matching.count,1,"\(mode) \(move): \(frames[0].log)")
                if let event=matching.first {
                    XCTAssertNotNil(PokeRogueOriginalCatalog.shared.entry(event),move)
                    if move=="geomancy" {XCTAssertEqual(event.phase,"charge")}
                    if ["mistyterrain","fairylock"].contains(move) {
                        XCTAssertEqual(event.phase,"field")
                        XCTAssertTrue(BattleFieldEffects.isGlobal(event))
                        XCTAssertNotNil(L(.ko).battleFieldDescription(move))
                    }
                }
                let name=BattleTextCatalog.shared.moveName(move,language:.ko)
                XCTAssertTrue(presentation.messages.values.contains{$0.contains(name)},move)
                engine.stop()
            }
        }
    }

}
