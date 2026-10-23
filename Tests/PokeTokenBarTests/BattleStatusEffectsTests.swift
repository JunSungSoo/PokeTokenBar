import AppKit
import CryptoKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor final class BattleStatusEffectsTests: XCTestCase {
    struct Sample: Decodable { let mode: String; let status: String; let player: Int; let frame: BattleFrame }
    func samples() throws -> [Sample] {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let child=Process(),output=Pipe()
        child.executableURL=root.appendingPathComponent("BattleEngine/runtime/node")
        child.arguments=[root.appendingPathComponent("BattleEngine/tests/fixtures/status-effects.cjs").path]
        child.standardOutput=output;try child.run()
        let data=output.fileHandleForReading.readDataToEndOfFile();child.waitUntilExit()
        XCTAssertEqual(child.terminationStatus,0)
        return try JSONDecoder().decode([Sample].self,from:data)
    }
    func testRealBW2StatusActivationsBothFormatsAndPerspectives() throws {
        var keys=Set<String>(),blocked=Set<String>(),slots=Set<BattleEffectPosition>()
        for sample in try samples() {
            let frame=sample.frame,presentation=BattlePresentationEvents(frame:frame,language:.ko,ownPlayer:sample.player)
            XCTAssertEqual(Set(presentation.events.map(\.id)).count,presentation.events.count)
            for scene in frame.scenes ?? [] {
                let line=frame.log[scene.id-(frame.logOffset ?? 0)]
                let parts=line.split(separator:"|",omittingEmptySubsequences:false).map(String.init)
                let event=try XCTUnwrap(presentation.events.first{$0.id==scene.id})
                let activation=line.hasPrefix("|-status|") || line.hasPrefix("|-start|") || line.hasPrefix("|-activate|") || line.hasPrefix("|cant|") && ["slp","par","frz"].contains(parts[3]) || line.hasPrefix("|-damage|") && (line.contains("[from] psn") || line.contains("[from] brn"))
                if activation {
                    XCTAssertEqual(event.phase,"status",line)
                    XCTAssertEqual(event.moveID,BattleStatusEffects.animations[sample.status],line)
                    keys.insert(try XCTUnwrap(event.moveID));slots.insert(event.source)
                    if parts[1]=="cant" { blocked.insert(parts[3]) }
                    let token=parts[2].split(separator:":")[0]
                    XCTAssertEqual(event.source.own,token.hasPrefix("p\(sample.player+1)"))
                    XCTAssertEqual(event.source.slot,token.hasSuffix("b") ? 1:0)
                    XCTAssertEqual(event.targets,[BattleEffectTarget(position:event.source,hit:true)])
                    XCTAssertNotNil(PokeRogueOriginalCatalog.shared.entry(event))
                    XCTAssertNotNil(presentation.messages[event.id])
                } else { XCTAssertNotEqual(event.phase,"status",line) }
            }
        }
        XCTAssertEqual(keys,Set(BattleStatusEffects.animations.values))
        XCTAssertEqual(blocked,["slp","par","frz"])
        XCTAssertEqual(slots.count,4)
    }
    func testNonActivationBranchesAndAbilityCausedStatusKeepLocalizedNotice() throws {
        let frame=try XCTUnwrap(samples().first?.frame),scene=try XCTUnwrap(frame.scenes?.first)
        for line in ["", "|cant|p1a: A", "|cant|p9z: A|slp", "|cant|p3a: A|slp", "|cant|p1c: A|slp", "|cant|x1a: A|slp", "|cant|p1: A|slp", "|cant|p1a: A|flinch", "|cant|p1a: A|Attract", "|-status|p1a: A|unknown", "|-activate|p1a: A|ability: Flash Fire", "|-damage|p1a: A|50/100", "|-damage|p1a: A|50/100|[from] confusion", "|-curestatus|p1a: A|slp", "|move|p1a: A|Sleep Talk"] {
            XCTAssertNil(BattleStatusEffects.event(scene:scene,line:line,ownPlayer:0),line)
        }
        let log=["|-status|p1a: Pikachu|par|[from] ability: Static|[of] p2a: Pikachu"]
        let adjusted=BattleFrame(revision:frame.revision,turn:frame.turn,decisionID:frame.decisionID,preview:frame.preview,waiting:frame.waiting,own:frame.own,foe:frame.foe,slots:frame.slots,log:log,effects:[],field:frame.field,logOffset:scene.id,scenes:[scene],ended:false,winner:nil)
        for language in AppLanguage.allCases {
            let events=BattlePresentationEvents(frame:adjusted,language:language,ownPlayer:0)
            XCTAssertEqual(events.events.count,1);XCTAssertEqual(events.events.first?.phase,"status")
            XCTAssertEqual(events.messages[scene.id],BattleLogText.describe(log[0],language:language))
        }
        let root=PokeRogueOriginalCatalog.directory
        let manifest=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("manifest.json"))) as? [String:Any])
        let hashes=try XCTUnwrap(manifest["sha256"] as? [String:String])
        let originals=try XCTUnwrap(manifest["originalPaths"] as? [String:String])
        for entry in try XCTUnwrap(PokeRogueOriginalCatalog.shared.manifest.statusEntries).values {
            for path in [entry.file]+entry.graphics.map({"images/battle_anims/\($0).png"})+entry.sounds.map({"audio/battle_anims/\($0)"}) {
                XCTAssertNotNil(originals[path])
                XCTAssertEqual(SHA256.hash(data:try Data(contentsOf:root.appendingPathComponent(path))).map{String(format:"%02x",$0)}.joined(),hashes[path])
            }
        }
    }
    func testPoisonDamageWaitsForOriginalAnimationAndThenAdvancesQueue() async throws {
        for doubles in [false,true] {
            let (store,directory)=try PokeRogueFaithfulTests().gifStore()
            defer{try? FileManager.default.removeItem(at:directory)}
            let player=PokeRogueBattlePlayer(spriteStore:store),probe=StatusQueueProbe()
            let width:CGFloat=doubles ? 680:660
            let host=NSHostingController(rootView:StatusQueueFixture(player:player,probe:probe,doubles:doubles))
            let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:width,height:310),styleMask:[.borderless],backing:.buffered,defer:false)
            window.contentViewController=host;window.orderFront(nil)
            defer{player.stop();window.orderOut(nil);window.contentViewController=nil}
            let deadline=Date().addingTimeInterval(15)
            var gifs=Set<Int>(),sawPlaying=false
            while !probe.finished,Date()<deadline {
                if player.isPlaying {
                    sawPlaying=true;XCTAssertEqual(probe.hp,100,"Poison HP must stay unchanged during its original animation")
                    let state=try await player.inspect()
                    if let actor=(state["actors"] as? [[String:Any]])?.first,let gif=actor["gif"] as? Int {gifs.insert(gif)}
                }
                try await Task.sleep(for:.milliseconds(35))
            }
            XCTAssertTrue(probe.finished,player.error ?? "Queue timeout")
            XCTAssertTrue(sawPlaying);XCTAssertGreaterThan(gifs.count,1)
            XCTAssertEqual(probe.scenes,[1,2]);XCTAssertEqual(probe.hp,75)
            XCTAssertFalse(probe.committedWhilePlaying)
            XCTAssertNil(player.error)
        }
    }
    func testOriginalStatusPlayerParticlesToneAudioAndCleanupOffscreen() async throws {
        let (store,directory)=try PokeRogueFaithfulTests().gifStore();defer{try? FileManager.default.removeItem(at:directory)}
        let player=PokeRogueBattlePlayer(spriteStore:store)
        let host=NSHostingController(rootView:Color.clear.modifier(PokeRogueBattlefieldLayers(player:player)).frame(width:680,height:310))
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:680,height:310),styleMask:[.borderless],backing:.buffered,defer:false)
        XCTAssertTrue(NSScreen.screens.allSatisfy{!$0.frame.intersects(window.frame)})
        window.contentViewController=host;window.orderFront(nil)
        defer{player.stop();window.orderOut(nil);window.contentViewController=nil}
        await player.start();let deadline=Date().addingTimeInterval(15)
        while !player.ready,player.error==nil,Date()<deadline {try await Task.sleep(for:.milliseconds(30))}
        XCTAssertTrue(player.ready,player.error ?? "Player not ready");guard player.ready else{return}
        let sprite=try await PokeRogueFaithfulPlayer.spritePayload(back:true,store:store)
        let result=try await player.evaluate("""
        const failures=[],captures={};let particles=0,tones=0,sounds=0;
        for(const width of [660,680])for(const own of [true,false])for(const move of keys){
          const source=own?'own-0':'foe-0';
          const actors=[{key:'own-0',own:true,slot:0,texture:'status-gif',sprite,x:120,y:280},{key:'foe-0',own:false,slot:0,texture:'status-gif',sprite,x:520,y:140}];
          if(width===680)actors.push({key:'own-1',own:true,slot:1,texture:'status-gif',sprite,x:240,y:280},{key:'foe-1',own:false,slot:1,texture:'status-gif',sprite,x:410,y:140});
          await window.ptbPrepare({move,actors,source,targets:[{key:source}],hit:true,width,height:310,scale:1.5,effectsVolume:.2});
          let seen=false,tone=false;
          for(let i=0;i<100;i++){
            window.ptbAdvance(50);const state=window.ptbInspect();
            if(width===660&&own&&i===8&&['commonsleep','commonpoison'].includes(move))captures[move]=document.querySelector('canvas').toDataURL();
            seen ||= state.sprites.some(s=>s.texture==='PRAS- Status'&&s.visible);
            tone ||= state.sprites.some(a=>a.actor===source&&a.tone.some(v=>v!==0));
            if(state.sprites.some(a=>a.actor&&a.actor!==source&&a.tone.some(v=>v!==0)))failures.push(move+': tone leaked to another Pokémon');
          }
          const state=window.ptbInspect();sounds+=state.soundEvents.length;
          if(!state.done)failures.push(move+': did not complete');
          if(!state.soundEvents.length)failures.push(move+': no original sound');
          if(move==='commonsleep'&&!seen)failures.push('Missing sleep Zzz sprite');
          if(move==='commonpoison'&&!tone)failures.push('Missing poison purple flash');
          if(seen)particles++;if(tone)tones++;
          window.ptbFinish();if(window.ptbInspect().actors.length)failures.push(move+': actors not cleaned up');
        }
        return {failures,particles,tones,sounds,captures};
        """,arguments:["sprite":sprite,"keys":Array(BattleStatusEffects.animations.values).sorted()])
        let state=try XCTUnwrap(result as? [String:Any])
        XCTAssertEqual(state["failures"] as? [String],[])
        XCTAssertGreaterThan(state["particles"] as? Int ?? 0,0)
        XCTAssertGreaterThan(state["tones"] as? Int ?? 0,0)
        XCTAssertGreaterThan(state["sounds"] as? Int ?? 0,0)
        if let captures=state["captures"] as? [String:String] {
            for (name,url) in captures {
                let encoded=String(url.split(separator:",",maxSplits:1)[1])
                try XCTUnwrap(Data(base64Encoded:encoded)).write(to:URL(fileURLWithPath:"/tmp/ptb-status-\(name).png"))
            }
        }
        XCTAssertNil(player.error)
    }
}

@MainActor private final class StatusQueueProbe {
    var hp=100;var scenes:[Int]=[];var finished=false;var committedWhilePlaying=false
}
@MainActor private struct StatusQueueFixture:View {
    let player:PokeRogueBattlePlayer;let probe:StatusQueueProbe;let doubles:Bool
    @State private var events:[BattleVisualEvent]=[]
    @State private var busy=false
    @State private var playback:BattleEffectPlayback?
    private func pokemon(_ id:String,hp:Int=100)->BattleCombatant {
        BattleCombatant(id:id,speciesID:25,name:"Pikachu",level:50,shiny:false,active:true,form:nil,fainted:false,hp:hp,maxHP:100,status:"psn",stats:nil)
    }
    var body:some View {
        let positions=(0..<(doubles ? 4:2)).map{BattleEffectPosition(own:$0%2==0,slot:$0/2)}
        let actors=positions.map{p in PokeRogueActor(pokemon:pokemon(p.key),position:p,rect:CGRect(x:p.own ? 40+p.slot*100:450+p.slot*50,y:p.own ? 160:30,width:100,height:110))}
        let field=BattleFieldState(weather:"",weatherSuppressed:false,conditions:[],ownSide:[],foeSide:[])
        let own=[pokemon("own-0",hp:75)]+(doubles ? [pokemon("own-1")]:[])
        let foe=[pokemon("foe-0")]+(doubles ? [pokemon("foe-1")]:[])
        let scenes=Dictionary(uniqueKeysWithValues:[1,2].map{($0,BattleScene(id:$0,turn:2,own:own,foe:foe,field:field))})
        Color.clear.modifier(PokeRogueBattlefieldLayers(player:player)).overlay{
            BattleEffectsLayer(events:events,rects:Dictionary(uniqueKeysWithValues:actors.map{($0.position.key,$0.rect)}),busy:$busy,playback:$playback,scenes:scenes,
                onScene:{scene in probe.scenes.append(scene.id);probe.hp=scene.own[0].hp;probe.committedWhilePlaying = probe.committedWhilePlaying || player.isPlaying},
                onFinished:{probe.finished=true},originalPlayer:player,actors:actors,viewport:CGSize(width:doubles ? 680:660,height:310))
        }.frame(width:doubles ? 680:660,height:310)
        .task{
            try? await Task.sleep(for:.milliseconds(100))
            let source=BattleEffectPosition(own:true,slot:0)
            events=[BattleVisualEvent(id:1,move:"commonpoison",type:"",category:"Status",source:source,targets:[BattleEffectTarget(position:source,hit:true)],moveID:"commonpoison",phase:"status"),
                BattleVisualEvent(id:2,move:"",type:"",category:"Status",source:source,targets:[],phase:"state")]
        }
    }
}
