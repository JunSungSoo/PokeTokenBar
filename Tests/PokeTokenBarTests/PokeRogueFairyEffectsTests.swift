import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor final class PokeRogueFairyEffectsTests:XCTestCase {
    private func wait(_ condition:()->Bool) async throws {
        let end=Date().addingTimeInterval(20)
        while !condition(),Date()<end {try await Task.sleep(for:.milliseconds(25))}
        XCTAssertTrue(condition())
    }
    func testProductionBridgeKeepsGifCadenceAndVolumeForFairyAttackAndGlobalTerrain() async throws {
        let (store,directory)=try PokeRogueFaithfulTests().gifStore()
        defer {try? FileManager.default.removeItem(at:directory)}
        let player=PokeRogueBattlePlayer(spriteStore:store)
        let host=NSHostingController(rootView:Color.clear.frame(width:680,height:350).modifier(PokeRogueBattlefieldLayers(player:player)))
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:680,height:350),styleMask:[.borderless],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.contentViewController=host;window.orderFront(nil)
        defer {player.stop();window.orderOut(nil);window.contentViewController=nil}
        player.setEffectsVolume(0.24)
        for doubles in [false,true] {
            let actors=(0..<(doubles ? 4:2)).map {i -> PokeRogueActor in
                let own=i%2==0,slot=i/2
                let pokemon=BattleCombatant(id:String(i),speciesID:25,name:"Pikachu",level:50,shiny:false,active:true,form:nil,fainted:false,hp:100,maxHP:100,status:"",stats:nil)
                return PokeRogueActor(pokemon:pokemon,position:.init(own:own,slot:slot),rect:CGRect(x:own ? 40+slot*130:400+slot*130,y:own ? 180:40,width:100,height:120))
            }
            for move in ["moonblast","mistyterrain"] {
                let global=move=="mistyterrain"
                let targets=actors.filter{global || !$0.position.own}.map{BattleEffectTarget(position:$0.position,hit:true)}
                let event=BattleVisualEvent(id:1,move:move,type:"Fairy",category:global ? "Status":"Special",source:.init(own:true,slot:0),targets:targets,moveID:move,phase:global ? "field":"move")
                let task=Task{await player.play(event,actors:actors,size:CGSize(width:680,height:350))}
                try await wait{player.isPlaying || player.error != nil}
                XCTAssertNil(player.error)
                var gifFrames=Set<Int>()
                for _ in 0..<6 {
                    let state=try await player.inspect()
                    for actor in state["actors"] as? [[String:Any]] ?? [] {if let gif=actor["gif"] as? Int {gifFrames.insert(gif)}}
                    XCTAssertEqual(try XCTUnwrap(state["effectsVolume"] as? Double),0.24,accuracy:0.000001)
                    try await Task.sleep(for:.milliseconds(55))
                }
                XCTAssertGreaterThan(gifFrames.count,1,"Existing GIF frames must continue during the original effect")
                let complete=await task.value
                XCTAssertTrue(complete,move+": "+(player.error ?? "no error"))
                let state=try await player.inspect()
                XCTAssertEqual(state["done"] as? Bool,true)
                XCTAssertEqual(state["tracks"] as? Int,0)
            }
        }
    }
    func testEveryFairyTimelineExecutesInBothFormatsDirectionsAndLayers() async throws {
        let (store,directory)=try PokeRogueFaithfulTests().gifStore()
        defer {try? FileManager.default.removeItem(at:directory)}
        let player=PokeRogueBattlePlayer(spriteStore:store)
        let host=NSHostingController(rootView:Color.clear.frame(width:680,height:350).modifier(PokeRogueBattlefieldLayers(player:player)))
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:680,height:350),styleMask:[.borderless],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.contentViewController=host;window.orderFront(nil)
        defer {player.stop();window.orderOut(nil);window.contentViewController=nil}
        await player.start();try await wait{player.ready || player.error != nil}
        XCTAssertNil(player.error);guard player.ready else{return}
        let sprite=try await PokeRogueFaithfulPlayer.spritePayload(back:true,store:store)
        let ids=PokemonFairyMoves.shared.moves.keys.sorted()+["geomancy:charge"]
        let withSound=ids.filter{!(PokeRogueOriginalCatalog.shared.manifest.entries[$0]?.sounds.isEmpty ?? true)}
        for doubles in [false,true] {for reverse in [false,true] {
            for background in [true,false] {
                let result=try await player.evaluate("""
                const errors=[],results=[];
                for(const move of moves) {
                    try {
                        const actors=[];
                        for(let slot=0;slot<(doubles?2:1);slot++)for(const own of [true,false])actors.push({key:(own?'own-':'foe-')+slot,own,slot,texture:'fairy-fixture',sprite,x:own?95+slot*155:450+slot*145,y:own?310:155});
                        const source=reverse?'foe-0':'own-0';
                        let targets=actors.filter(a=>a.own===reverse).map(a=>({key:a.key}));
                        if(['geomancy','geomancy:charge','craftyshield'].includes(move))targets=actors.filter(a=>a.own===!reverse).map(a=>({key:a.key}));
                        if(move==='aromaticmist')targets=[{key:(reverse?'foe-':'own-')+(doubles?'1':'0')}];
                        const globalField=['mistyterrain','fairylock'].includes(move);
                        if(globalField||move==='flowershield')targets=actors.map(a=>({key:a.key}));
                        const prepared=await window.ptbPrepare({move,actors,source,targets,hit:true,globalField,width:doubles?680:660,height:350,scale:doubles?1.1:1.5,effectsVolume:.2});
                        let visuals=0,soundCount=0,animated=false;
                        for(let frame=0;frame<prepared.frames+40;frame++) {
                            window.ptbAdvance(50);const state=window.ptbInspect();
                            visuals=Math.max(visuals,state.graphics+(state.backdrops?.length??0));
                            soundCount=Math.max(soundCount,state.soundEvents?.length??0);
                            animated=animated||state.sprites.some(s=>s.actor&&s.visible);
                        }
                        const finished=window.ptbAdvance(120000);
                        if(!finished.done)throw Error('Timeline did not finish');
                        soundCount=Math.max(soundCount,window.ptbInspect().soundEvents.length);
                        if(!background&&withSound.includes(move)&&soundCount===0)throw Error('No original sound event played');
                        if(!background&&move!=='aromaticmist'&&visuals===0)throw Error('No original foreground graphics');
                        results.push({move,visuals,soundCount,animated});
                    }catch(error){errors.push(move+': '+String(error)+' '+error.stack);}
                    window.ptbFinish();
                    const cleared=window.ptbInspect();
                    if(cleared.tracks!==0||cleared.soundInstances!==0)errors.push(move+': cleanup leak');
                }
                return {errors,results};
                """,arguments:["moves":ids,"doubles":doubles,"reverse":reverse,"sprite":sprite,"background":background,"withSound":withSound],background:background)
                XCTAssertEqual(result["errors"] as? [String],[],"\(doubles) \(reverse) \(background): \(result)")
                XCTAssertEqual((result["results"] as? [[String:Any]])?.count,15)
            }
        }}
        XCTAssertNil(player.error)
    }
}
