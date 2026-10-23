import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor final class BattleWeatherHitTests:XCTestCase {
    func frames() throws -> [BattleFrame] {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let child=Process(),output=Pipe()
        child.executableURL=root.appendingPathComponent("BattleEngine/runtime/node")
        child.arguments=[root.appendingPathComponent("BattleEngine/tests/fixtures/field-effects.cjs").path]
        child.standardOutput=output;try child.run()
        let data=output.fileHandleForReading.readDataToEndOfFile();child.waitUntilExit()
        XCTAssertEqual(child.terminationStatus,0)
        return try JSONDecoder().decode([BattleFrame].self,from:data)
    }
    func testAuthoritativeWeatherDamageBothPerspectivesAndSlotsWithoutNotices() throws {
        let frames=try frames();var slots=Set<BattleEffectPosition>(),weather=Set<String>()
        for frame in frames {
            for player in [0,1] {
                let events=BattlePresentationEvents(frame:frame,language:.ko,ownPlayer:player)
                for scene in frame.scenes ?? [] {
                    let line=frame.log[scene.id-(frame.logOffset ?? 0)]
                    let event=BattleWeatherHitEffects.event(scene:scene,line:line,ownPlayer:player)
                    if let event {
                        XCTAssertEqual(events.events.first{$0.id==scene.id}?.phase,"weather-hit")
                        XCTAssertNil(events.messages[scene.id]);XCTAssertEqual(event.targets,[.init(position:event.source,hit:true)])
                        let token=line.split(separator:"|")[1]
                        XCTAssertEqual(event.source.own,token.hasPrefix("p\(player+1)"))
                        XCTAssertEqual(event.source.slot,token.hasPrefix("p1b") || token.hasPrefix("p2b") ? 1:0)
                        slots.insert(event.source);weather.insert(event.moveID!)
                    } else { XCTAssertFalse(events.events.contains{$0.id==scene.id && $0.phase=="weather-hit"},line) }
                }
            }
        }
        XCTAssertEqual(slots.count,4);XCTAssertEqual(weather,["sandstorm","hail"])
        let suppressed=try XCTUnwrap(frames.last)
        XCTAssertTrue(suppressed.field!.weatherSuppressed)
        XCTAssertFalse(BattlePresentationEvents(frame:suppressed,language:.ko,ownPlayer:0).events.contains{$0.phase=="weather-hit"})
        // Original engine's immune lead never emits weather damage; its vulnerable partner still does.
        for frame in frames.suffix(9).dropLast() {
            if [248,460].contains(frame.own[0].speciesID) {
                let events=BattlePresentationEvents(frame:frame,language:.ko,ownPlayer:0)
                XCTAssertFalse(events.events.contains{$0.phase=="weather-hit" && $0.source == .init(own:true,slot:0)})
            }
        }
    }
    func testOriginalHitAudioBlinkAndVolumeOnBothSurfacesOffscreen() async throws {
        let (store,directory)=try PokeRogueFaithfulTests().gifStore();defer{try? FileManager.default.removeItem(at:directory)}
        let player=PokeRogueBattlePlayer(spriteStore:store)
        let host=NSHostingController(rootView:Color.clear.modifier(PokeRogueBattlefieldLayers(player:player)).frame(width:680,height:310))
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:680,height:310),styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentViewController=host;window.orderFront(nil)
        defer{player.stop();window.orderOut(nil);window.contentViewController=nil}
        await player.start();let deadline=Date().addingTimeInterval(15)
        while !player.ready,player.error==nil,Date()<deadline{try await Task.sleep(for:.milliseconds(25))}
        XCTAssertTrue(player.ready,player.error ?? "Not ready");guard player.ready else{return}
        let sprite=try await PokeRogueFaithfulPlayer.spritePayload(back:true,store:store)
        for background in [false,true] {
            let result=try await player.evaluate("""
            const failures=[];
            const keys=['own-0','own-1','foe-0','foe-1'];
            for(const source of keys){
              const actors=keys.map((key,i)=>({key,own:i<2,slot:i%2,texture:'weather-gif',sprite,x:100+i*120,y:220}));
              window.ptbSetEffectsVolume(.23);await new Promise(r=>setTimeout(r,30));
              await window.ptbPrepare({weatherHit:true,move:'sandstorm',actors,source,targets:[{key:source}],hit:true,width:680,height:310,scale:1.5,effectsVolume:.23});
              await new Promise(r=>setTimeout(r,30));const initial=window.ptbInspect();
              if(initial.weatherHit.visible)failures.push('No initial hit blink');
              if(initial.soundEvents.length !== (initial.layer==='foreground'?1:0))failures.push('Sound missing or duplicated across surfaces');
              if(initial.layer==='foreground'&&(initial.soundEvents[0].key!=='weather-hit'||Math.abs(initial.soundEvents[0].volume-.23)>.001||initial.audioState!=='running'||initial.playingSounds<1||Math.abs(initial.effectsVolume-.23)>.001))failures.push('Original hit is not audible '+JSON.stringify({sound:initial.soundEvents[0],state:initial.audioState,playing:initial.playingSounds}));
              for(const visible of [true,false,true,false,true]){
                window.ptbAdvance(100);const s=window.ptbInspect();
                if(s.weatherHit.visible!==visible)failures.push('Incorrect 100ms blink');
                if(s.sprites.some(a=>a.actor&&a.actor!==source&&!a.visible))failures.push('Blink leaked to another Pokemon');
              }
              if(!window.ptbInspect().done)failures.push('Hit did not finish before HP');
              window.ptbSetEffectsVolume(0);await new Promise(r=>setTimeout(r,30));if(window.ptbInspect().effectsVolume!==0)failures.push('Live mute failed '+window.ptbInspect().effectsVolume);
              window.ptbSetEffectsVolume(.6);await new Promise(r=>setTimeout(r,30));if(Math.abs(window.ptbInspect().effectsVolume-(initial.layer==='foreground'?.6:0))>.001)failures.push('Live volume failed '+window.ptbInspect().effectsVolume);
              window.ptbFinish();if(window.ptbInspect().actors.length)failures.push('Cleanup failed');
            }
            return {failures};
            """,arguments:["sprite":sprite],background:background)
            XCTAssertEqual(result["failures"] as? [String],[])
        }
        XCTAssertNil(player.error)
    }
    func testWeatherQueueWaitsForHitThenSmoothHPBeforeNextScene() async throws {
        let (store,directory)=try PokeRogueFaithfulTests().gifStore();defer{try? FileManager.default.removeItem(at:directory)}
        let player=PokeRogueBattlePlayer(spriteStore:store),probe=WeatherQueueProbe()
        player.setEffectsVolume(0.2)
        let host=NSHostingController(rootView:WeatherQueueFixture(player:player,probe:probe))
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:660,height:310),styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentViewController=host;window.orderFront(nil)
        defer{player.stop();window.orderOut(nil);window.contentViewController=nil}
        let deadline=Date().addingTimeInterval(15);var sawPlaying=false,intermediate=false,gifs=Set<Int>()
        while !probe.finished,Date()<deadline {
            if player.isPlaying {
                sawPlaying=true;XCTAssertEqual(probe.state.frame?.own[0].hp,100)
                let s=try await player.inspect()
                if let actor=(s["actors"] as? [[String:Any]])?.first,let gif=actor["gif"] as? Int{gifs.insert(gif)}
            }
            if let hp=probe.state.frame?.own[0].hp,hp>75,hp<100 {intermediate=true;XCTAssertEqual(probe.scenes,[1]);XCTAssertFalse(player.isPlaying)}
            try await Task.sleep(for:.milliseconds(20))
        }
        XCTAssertTrue(probe.finished,player.error ?? "Queue timeout");XCTAssertTrue(sawPlaying);XCTAssertTrue(intermediate)
        XCTAssertGreaterThan(gifs.count,1);XCTAssertEqual(probe.scenes,[1,2]);XCTAssertEqual(probe.state.frame?.own[0].hp,75);XCTAssertNil(player.error)
    }
}
@MainActor private final class WeatherQueueProbe {let state=BattleScenePlayback();var scenes:[Int]=[];var finished=false}
@MainActor private struct WeatherQueueFixture:View {
    let player:PokeRogueBattlePlayer;let probe:WeatherQueueProbe
    @State private var events:[BattleVisualEvent]=[]
    @State private var busy=false
    @State private var playback:BattleEffectPlayback?
    private func pokemon(_ id:String,hp:Int=100)->BattleCombatant{.init(id:id,speciesID:25,name:"Pikachu",level:50,shiny:false,active:true,form:nil,fainted:false,hp:hp,maxHP:100,status:"",stats:nil)}
    var body:some View {
        let own=BattleEffectPosition(own:true,slot:0),foe=BattleEffectPosition(own:false,slot:0)
        let field=BattleFieldState(weather:"sandstorm",weatherSuppressed:false,conditions:[],ownSide:[],foeSide:[])
        let actors=[PokeRogueActor(pokemon:pokemon("own"),position:own,rect:CGRect(x:70,y:160,width:100,height:100)),PokeRogueActor(pokemon:pokemon("foe"),position:foe,rect:CGRect(x:470,y:30,width:100,height:100))]
        let scenes=Dictionary(uniqueKeysWithValues:[1,2].map{($0,BattleScene(id:$0,turn:2,own:[pokemon("own",hp:75)],foe:[pokemon("foe")],field:field))})
        Color.clear.modifier(PokeRogueBattlefieldLayers(player:player)).overlay{
            BattleEffectsLayer(events:events,rects:Dictionary(uniqueKeysWithValues:actors.map{($0.position.key,$0.rect)}),busy:$busy,playback:$playback,scenes:scenes,
                onScene:{probe.state.apply($0)},onFinished:{probe.finished=true},onAnimatedScene:{probe.scenes.append($0.id);await probe.state.animate($0)},originalPlayer:player,actors:actors,viewport:CGSize(width:660,height:310))
        }.frame(width:660,height:310).task{
            probe.state.accept(BattleFrame(revision:"weather",turn:1,decisionID:"1",preview:false,waiting:false,own:[pokemon("own")],foe:[pokemon("foe")],slots:[],log:[],effects:[],field:field,ended:false,winner:nil))
            try? await Task.sleep(for:.milliseconds(100))
            events=[.init(id:1,move:"sandstorm",type:"rock",category:"Status",source:own,targets:[.init(position:own,hit:true)],moveID:"sandstorm",phase:"weather-hit"),.init(id:2,move:"",type:"",category:"Status",source:own,targets:[],phase:"state")]
        }
    }
}
