import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor final class BattleCryTests:XCTestCase {
    func testNativeEntryCriesBothSidesRecallLowHPAndEffectsVolume() async throws {
        let (store,directory)=try PokeRogueFaithfulTests().gifStore();defer{try? FileManager.default.removeItem(at:directory)}
        let player=PokeRogueBattlePlayer(spriteStore:store)
        let host=NSHostingController(rootView:Color.clear.modifier(PokeRogueBattlefieldLayers(player:player)).frame(width:660,height:310))
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:660,height:310),styleMask:[.borderless],backing:.buffered,defer:false)
        XCTAssertTrue(NSScreen.screens.allSatisfy{!$0.frame.intersects(window.frame)})
        window.contentViewController=host;window.orderFront(nil)
        defer{player.stop();window.orderOut(nil);window.contentViewController=nil}
        for own in [true,false] { for recall in [false,true] {
            func actor(_ side:Bool,hp:Int,old:Bool=false)->PokeRogueActor {
                let p=BattleCombatant(id:(old ? "old-":"")+(side ? "own":"foe"),speciesID:25,name:"Pikachu",level:50,shiny:false,active:true,form:nil,fainted:false,hp:hp,maxHP:100,status:"",stats:nil)
                return PokeRogueActor(pokemon:p,position:.init(own:side,slot:0),rect:CGRect(x:side ? 40:450,y:side ? 160:30,width:100,height:110))
            }
            let actors=[actor(true,hp:recall ? 25:100),actor(false,hp:recall ? 25:100)]
            let source=BattleEffectPosition(own:own,slot:0)
            let event=BattleVisualEvent(id:1,move:"",type:"",category:"Status",source:source,targets:[],phase:"entry")
            player.setEffectsVolume(recall ? 0.6:0.2)
            var finished=false,result=false,seen:[String:Any]?,gifs=Set<Int>()
            let task=Task {result=await player.play(event,actors:actors,size:CGSize(width:660,height:310),previousActor:recall ? actor(own,hp:100,old:true):nil);finished=true}
            let deadline=Date().addingTimeInterval(15)
            while !finished,Date()<deadline {
                if player.isPlaying {
                    let state=try await player.inspect()
                    if let sound=(state["soundEvents"] as? [[String:Any]])?.first(where:{$0["key"] as? String=="cry/25"}) {
                        seen=sound
                        XCTAssertEqual((state["soundEvents"] as? [[String:Any]])?.filter{$0["key"] as? String=="cry/25"}.count,1)
                        let background=try await player.evaluate("return window.ptbInspect()",background:true) as? [String:Any]
                        XCTAssertTrue((background?["soundEvents"] as? [[String:Any]])?.isEmpty==true,"Background surface must not duplicate cries")
                    }
                    if let actor=(state["actors"] as? [[String:Any]])?.first,let gif=actor["gif"] as? Int{gifs.insert(gif)}
                }
                try await Task.sleep(for:.milliseconds(30))
            }
            if !finished{task.cancel()};await task.value
            XCTAssertTrue(result,player.error ?? "Entry did not finish")
            let sound=try XCTUnwrap(seen,"Both own and opponent entries/switches must cry")
            XCTAssertEqual(try XCTUnwrap(sound["volume"] as? Double),recall ? 0.6:0.2,accuracy:0.000001)
            XCTAssertEqual(sound["pitch"] as? Double,recall ? 0.85:1)
            XCTAssertEqual(try XCTUnwrap(sound["clock"] as? Double),recall ? 1720:720,accuracy:0.01)
            XCTAssertGreaterThan(gifs.count,1);XCTAssertNil(player.error)
        }}
    }
    func testWebAudioCryDecodesFormsMuteLiveVolumeAndSoundTail() async throws {
        let (store,directory)=try PokeRogueFaithfulTests().gifStore();defer{try? FileManager.default.removeItem(at:directory)}
        let player=PokeRogueBattlePlayer(spriteStore:store)
        let host=NSHostingController(rootView:Color.clear.modifier(PokeRogueBattlefieldLayers(player:player)).frame(width:660,height:310))
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:660,height:310),styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentViewController=host;window.orderFront(nil)
        defer{player.stop();window.orderOut(nil);window.contentViewController=nil}
        await player.start();let deadline=Date().addingTimeInterval(15)
        while !player.ready,player.error==nil,Date()<deadline{try await Task.sleep(for:.milliseconds(30))}
        XCTAssertTrue(player.ready,player.error ?? "Not ready");guard player.ready else{return}
        let sprite=try await PokeRogueFaithfulPlayer.spritePayload(back:true,store:store)
        let result=try await player.evaluate("""
        const failures=[];
        for(const [speciesID,form] of [[25,''],[143,''],[492,'sky'],[646,'black'],[646,'white'],[641,'therian'],[642,'therian'],[645,'therian']]){
          const payload={transition:true,actors:[{key:'own-0',own:true,slot:0,texture:'cry-test',sprite,x:120,y:280,speciesID,form,hpRatio:0.25}],source:'own-0',entrySources:['own-0'],targets:[],hit:true,width:660,height:310,scale:1.5,effectsVolume:0.2};
          const prepared=await window.ptbPrepare(payload);
          window.ptbAdvance(719);if(window.ptbInspect().soundEvents.some(s=>s.key.startsWith('cry/')))failures.push('early cry');
          window.ptbSetEffectsVolume(0.65);await new Promise(r=>setTimeout(r,60));window.ptbAdvance(1);
          const state=window.ptbInspect(),cry=state.soundEvents.find(s=>s.key.startsWith('cry/'));
          if(!cry||Math.abs(cry.volume-0.65)>0.000001||cry.pitch!==0.85)failures.push('volume/rate '+speciesID+form);
          if(state.entry.duration<720+prepared.audioTail*1000)failures.push('tail cut '+speciesID+form);
          window.ptbSetEffectsVolume(0);await new Promise(r=>setTimeout(r,60));if(window.ptbInspect().effectsVolume!==0)failures.push('mute failed');
          window.ptbAdvance(10000);if(!window.ptbInspect().done)failures.push('completion failed');window.ptbFinish();
        }
        return {failures};
        """,arguments:["sprite":sprite])
        XCTAssertEqual((result as? [String:Any])?["failures"] as? [String],[])
        XCTAssertNil(player.error)
    }
}
