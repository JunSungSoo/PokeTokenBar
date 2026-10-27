import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor final class BattleMegaEffectsTests:XCTestCase {
    private func pokemon(mega:Bool)->BattleCombatant {
        BattleCombatant(id:"same-owned-individual",speciesID:6,name:mega ? "Charizard-Mega-X":"Charizard",level:50,shiny:false,active:true,form:mega ? PokemonForm("mega-x"):nil,fainted:false,hp:350,maxHP:500,status:"",stats:nil,mega:mega)
    }
    private func store() throws -> (SpriteStore,URL) {
        let (store,directory)=try PokeRogueFaithfulTests().gifStore()
        for back in [false,true] {
            let source=directory.appendingPathComponent(SpriteStore.cacheKey(speciesID:25,animated:true,shiny:false,back:back)+".gif")
            let dest=directory.appendingPathComponent(SpriteStore.cacheKey(speciesID:6,animated:true,shiny:false,back:back)+".gif")
            try FileManager.default.copyItem(at:source,to:dest)
        }
        return (store,directory)
    }
    func testMegaEventsUseActualSideAndSlotInBothPerspectives() {
        let field=BattleFieldState(weather:"",weatherSuppressed:false,conditions:[],ownSide:[],foeSide:[])
        let scene=BattleScene(id:1,turn:1,own:[pokemon(mega:true)],foe:[pokemon(mega:false)],field:field)
        for player in [0,1] {for side in [1,2] {for slot in ["a","b"] {
            let event=BattleMegaEffects.event(scene:scene,line:"|-mega|p\(side)\(slot): Charizard|Charizard|Charizardite X",ownPlayer:player)
            XCTAssertEqual(event?.source,.init(own:side==player+1,slot:slot=="b" ? 1:0));XCTAssertEqual(event?.phase,"mega")
        }}}
        XCTAssertNil(BattleMegaEffects.event(scene:scene,line:"|-formechange|p1a: Charizard|Charizard-Mega-X",ownPlayer:0))
    }
    func testNativeMegaQueueWaitsForRevealBeforeNextSceneAndPreservesGIFs() async throws {
        let (store,directory)=try store();defer{try? FileManager.default.removeItem(at:directory)}
        let player=PokeRogueBattlePlayer(spriteStore:store),probe=MegaQueueProbe()
        let host=NSHostingController(rootView:MegaQueueFixture(player:player,probe:probe,before:pokemon(mega:false),after:pokemon(mega:true)))
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:660,height:330),styleMask:[.borderless],backing:.buffered,defer:false)
        XCTAssertTrue(NSScreen.screens.allSatisfy{!$0.frame.intersects(window.frame)})
        window.contentViewController=host;window.orderFront(nil)
        defer{player.stop();window.orderOut(nil);window.contentViewController=nil}
        var phases=Set<String>(),gifs=Set<Int>()
        let end=Date().addingTimeInterval(25)
        while !probe.finished,Date()<end {
            if player.isPlaying {
                let state=try await player.inspect()
                if let phase=(state["mega"] as? [String:Any])?["phase"] as? String{phases.insert(phase)}
                for actor in state["actors"] as? [[String:Any]] ?? [] {if let gif=actor["gif"] as? Int{gifs.insert(gif)}}
            }
            try await Task.sleep(for:.milliseconds(60))
        }
        XCTAssertTrue(probe.finished,player.error ?? "Mega queue timed out")
        XCTAssertEqual(probe.scenes,[0,2,3]);XCTAssertTrue(probe.revealedDuringPlayback)
        XCTAssertGreaterThan(try XCTUnwrap(probe.nextAt).timeIntervalSince(try XCTUnwrap(probe.started)),4.1)
        XCTAssertTrue(phases.isSuperset(of:["charge","arc","transform","gather","reveal","cry"]))
        XCTAssertGreaterThan(gifs.count,1);XCTAssertNil(player.error)
    }
    func testRealEngineMegaDefersDetailsChangeAndKeepsLocalizedMessages() throws {
        for frame in try BattleHeldItemTests().frames() {
            let deferred=BattleMegaEffects.deferredSceneIDs(frame:frame)
            for language in AppLanguage.allCases {
                let presentation=BattlePresentationEvents(frame:frame,language:language,ownPlayer:0)
                XCTAssertTrue(presentation.events.allSatisfy{!deferred.contains($0.id)})
                for (index,line) in frame.log.enumerated() where line.hasPrefix("|-mega|") {
                    let id=index+(frame.logOffset ?? 0)
                    XCTAssertEqual(presentation.events.first{$0.id==id}?.phase,"mega")
                    XCTAssertNotNil(presentation.messages[id])
                    XCTAssertTrue(deferred.contains(id-1),"The real engine precursor must be deferred")
                }
            }
        }
    }
    func testBothWebGLSurfacesMegaParticlesSoundVolumeAndCleanup() async throws {
        let (store,directory)=try store();defer{try? FileManager.default.removeItem(at:directory)}
        let player=PokeRogueBattlePlayer(spriteStore:store)
        let host=NSHostingController(rootView:Color.clear.modifier(PokeRogueBattlefieldLayers(player:player)).frame(width:680,height:330))
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:680,height:330),styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentViewController=host;window.orderFront(nil)
        defer{player.stop();window.orderOut(nil);window.contentViewController=nil}
        await player.start();let end=Date().addingTimeInterval(15)
        while !player.ready,player.error==nil,Date()<end {try await Task.sleep(for:.milliseconds(25))}
        XCTAssertTrue(player.ready,player.error ?? "Renderer unavailable");guard player.ready else{return}
        let sprite=try await PokeRogueFaithfulPlayer.spritePayload(back:true,store:store)
        for background in [false,true] {
            let result=try await player.evaluate("""
            const failures=[];
            for(const source of ['own-0','own-1','foe-0','foe-1']){
              const actors=['own-0','own-1','foe-0','foe-1'].map((key,i)=>({key,own:i<2,slot:i%2,texture:'mega-test',sprite,speciesID:6,form:'mega-x',hpRatio:.7,x:100+i*140,y:270}));
              await window.ptbPrepare({mega:true,actors,previousActors:[{...actors.find(a=>a.key===source),key:'mega-outgoing-'+source}],source,targets:[],width:680,height:330,scale:1,effectsVolume:.31});
              window.ptbAdvance(500);let s=window.ptbInspect();
              if(s.mega.incomingVisible||!s.mega.outgoingVisible||s.mega.particles<1||s.mega.backdropAlpha<=0)failures.push('Missing charge presentation '+source);
              window.ptbAdvance(2500);s=window.ptbInspect();
              if(!s.mega.incomingVisible||s.mega.outgoingVisible||s.mega.flashAlpha<=0)failures.push('Missing form reveal '+source);
              if(s.soundEvents.length!==(s.layer==='foreground'?4:0))failures.push('Duplicated/missing sounds');
              if(s.soundEvents.some(e=>Math.abs(e.volume-.31)>.001))failures.push('Effects volume ignored');
              window.ptbSetEffectsVolume(0);await new Promise(r=>setTimeout(r,30));if(window.ptbInspect().effectsVolume!==0)failures.push('Mute ignored');
              if(!window.ptbAdvance(30000).done)failures.push('Mega failed to finish');
              window.ptbFinish();s=window.ptbInspect();if(s.mega||s.actors.length||s.playingSounds)failures.push('Residual Mega scene');
            }
            return {failures};
            """,arguments:["sprite":sprite],background:background)
            XCTAssertEqual(result["failures"] as? [String],[])
        }
    }
    func testCancellingMegaDoesNotCommitAndReducedMotionCanRecover() async throws {
        let (store,directory)=try store();defer{try? FileManager.default.removeItem(at:directory)}
        let player=PokeRogueBattlePlayer(spriteStore:store)
        let host=NSHostingController(rootView:Color.clear.modifier(PokeRogueBattlefieldLayers(player:player)).frame(width:680,height:330))
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:680,height:330),styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentViewController=host;window.orderFront(nil)
        defer{player.stop();window.orderOut(nil);window.contentViewController=nil}
        let position=BattleEffectPosition(own:false,slot:1),rect=CGRect(x:450,y:20,width:150,height:160)
        let current=PokeRogueActor(pokemon:pokemon(mega:true),position:position,rect:rect)
        let old=PokeRogueActor(pokemon:pokemon(mega:false),position:position,rect:rect)
        let event=BattleVisualEvent(id:1,move:"",type:"",category:"Status",source:position,targets:[],phase:"mega")
        var commits=0
        let task=Task{await player.play(event,actors:[current],size:CGSize(width:680,height:330),previousActor:old,beforeFinish:{commits+=1})}
        let until=Date().addingTimeInterval(10)
        while !player.isPlaying,player.error==nil,Date()<until {try await Task.sleep(for:.milliseconds(25))}
        XCTAssertTrue(player.isPlaying,player.error ?? "Mega did not start");task.cancel()
        let cancelled=await task.value;XCTAssertFalse(cancelled);XCTAssertEqual(commits,0)
        let recovered=await player.play(event,actors:[current],size:CGSize(width:680,height:330),reducedMotion:true,previousActor:old,beforeFinish:{commits+=1})
        XCTAssertTrue(recovered,player.error ?? "Reduced motion did not recover");XCTAssertEqual(commits,1)
        XCTAssertFalse(player.isPlaying);XCTAssertNil(player.error)
    }
}
@MainActor private final class MegaQueueProbe {
    var scenes:[Int]=[];var started:Date?;var nextAt:Date?;var finished=false;var revealedDuringPlayback=false
}
@MainActor private struct MegaQueueFixture:View {
    let player:PokeRogueBattlePlayer;let probe:MegaQueueProbe;let before:BattleCombatant;let after:BattleCombatant
    @State private var events:[BattleVisualEvent]=[]
    @State private var busy=false
    var body:some View {
        let pos=BattleEffectPosition(own:true,slot:0),rect=CGRect(x:40,y:130,width:180,height:180)
        let field=BattleFieldState(weather:"",weatherSuppressed:false,conditions:[],ownSide:[],foeSide:[])
        let scenes=Dictionary(uniqueKeysWithValues:[0,1,2,3].map{($0,BattleScene(id:$0,turn:1,own:[$0==0 ? before:after],foe:[],field:field))})
        Color.clear.modifier(PokeRogueBattlefieldLayers(player:player)).overlay{
            BattleEffectsLayer(events:events,rects:[pos.key:rect],busy:$busy,scenes:scenes,onScene:{scene in
                probe.scenes.append(scene.id)
                if scene.id==2 {probe.revealedDuringPlayback=player.isPlaying}
                if scene.id==3 {probe.nextAt=Date()}
            },onFinished:{probe.finished=true},originalPlayer:player,actors:[PokeRogueActor(pokemon:before,position:pos,rect:rect)],viewport:CGSize(width:660,height:330))
        }.frame(width:660,height:330).task{
            try? await Task.sleep(for:.milliseconds(100));probe.started=Date()
            let frame=BattleFrame(revision:"fixture",turn:1,decisionID:"fixture",preview:false,waiting:false,own:[after],foe:[],slots:[],
                log:["|turn|1","|detailschange|p1a: Charizard|Charizard-Mega-X, L50","|-mega|p1a: Charizard|Charizard|Charizardite X","|turn|2"],
                scenes:scenes.values.sorted{$0.id<$1.id},ended:false,winner:nil)
            events=BattlePresentationEvents(frame:frame,language:.ko,ownPlayer:0).events
        }
    }
}
