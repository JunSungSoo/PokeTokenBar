import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class BattleEntryEffectsTests: XCTestCase {
    func testRealOpeningAndForcedReplacementSlotsInBothPerspectives() throws {
        struct Match:Decodable { let initial:[BattleFrame];let replaced:[BattleFrame] }
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let child=Process(),output=Pipe();child.executableURL=root.appendingPathComponent("BattleEngine/runtime/node")
        child.arguments=[root.appendingPathComponent("BattleEngine/tests/fixtures/action-scenes.cjs").path];child.standardOutput=output
        try child.run();let data=output.fileHandleForReading.readDataToEndOfFile();child.waitUntilExit();XCTAssertEqual(child.terminationStatus,0)
        let matches=try JSONDecoder().decode([String:Match].self,from:data)
        for (mode,match) in matches {
            for perspective in [0,1] {
                let frame=match.initial[perspective]
                let entries=BattlePresentationEvents(frame:frame,language:.ko,ownPlayer:perspective).events.filter{$0.phase=="entry"}
                XCTAssertEqual(entries.count,mode=="singles" ? 2:4)
                XCTAssertEqual(Set(entries.map(\.source)).count,entries.count)
                if mode=="doubles" {
                    XCTAssertTrue(BattleEntryEffects.canAppearTogether(entries[0],entries[1]))
                    XCTAssertFalse(BattleEntryEffects.canAppearTogether(entries[1],entries[2]))
                    XCTAssertFalse(BattleEntryEffects.canAppearTogether(entries[0],entries[0]))
                }
                for e in entries { XCTAssertGreaterThan(PokeRogueOriginalCatalog.shared.estimatedDuration(e),3) }
                let later=BattlePresentationEvents(frame:match.replaced[perspective],language:.ko,ownPlayer:perspective).events.filter{$0.phase=="entry" && $0.id>(frame.scenes?.last?.id ?? -1)}
                XCTAssertEqual(later.count,mode=="singles" ? 1:2)
                XCTAssertTrue(later.allSatisfy{$0.source.own == (perspective==1)})
                let scene=try XCTUnwrap(frame.scenes?.first)
                XCTAssertNil(BattleEntryEffects.event(scene:scene,line:"|replace|p1a: Pikachu|Pikachu",ownPlayer:perspective))
                XCTAssertNil(BattleEntryEffects.event(scene:scene,line:"|switch|p9z: bad",ownPlayer:perspective))
                XCTAssertNil(BattleEntryEffects.event(scene:scene,line:"|switch",ownPlayer:perspective))
            }
        }
    }
    func testNativeEntryCommitsOnceBeforeTheFollowingStateAndRetainsGIFs() async throws {
        for (doubles,fainted,shiny) in [(false,false,false),(true,false,false),(false,true,false),(false,false,true),(true,false,true)] {
            let (store,directory)=try PokeRogueFaithfulTests().gifStore()
            defer{try? FileManager.default.removeItem(at:directory)}
            if shiny {
                for back in [false,true] {
                    let original=directory.appendingPathComponent(SpriteStore.cacheKey(speciesID:25,animated:true,shiny:false,back:back)+".gif")
                    try FileManager.default.copyItem(at:original,to:directory.appendingPathComponent(SpriteStore.cacheKey(speciesID:25,animated:true,shiny:true,back:back)+".gif"))
                }
            }
            let player=PokeRogueBattlePlayer(spriteStore:store),probe=EntryQueueProbe()
            let host=NSHostingController(rootView:EntryQueueFixture(player:player,probe:probe,doubles:doubles,fainted:fainted,shiny:shiny))
            let width:CGFloat=doubles ? 680:660
            let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:width,height:310),styleMask:[.borderless],backing:.buffered,defer:false)
            window.contentViewController=host;window.orderFront(nil)
            defer{player.stop();window.orderOut(nil);window.contentViewController=nil}
            let end=Date().addingTimeInterval(15)
            var sawSparkle=false
            var gifs=Set<Int>(),recalls=Set<Bool>(),trackCounts=Set<Int>()
            while !probe.finished,Date()<end {
                if player.isPlaying {
                    let state=try await player.inspect()
                    if let tracks=state["entries"] as? [[String:Any]] { trackCounts.insert(tracks.count); if tracks.count==2 { XCTAssertEqual(tracks[0]["elapsed"] as? Double,tracks[1]["elapsed"] as? Double) } }
                    if let tracks=state["entries"] as? [[String:Any]],tracks.contains(where:{$0["phase"] as? String=="sparkle"}) {sawSparkle=true}
                    if let recall=(state["entry"] as? [String:Any])?["recall"] as? Bool{recalls.insert(recall)}
                    if let actor=(state["actors"] as? [[String:Any]])?.first,let gif=actor["gif"] as? Int{gifs.insert(gif)}
                }
                try await Task.sleep(for:.milliseconds(35))
            }
            XCTAssertTrue(probe.finished,player.error ?? "Queue did not finish")
            XCTAssertEqual(trackCounts,[doubles ? 2:1])
            XCTAssertEqual(probe.scenes,doubles ? [1,2,3]:[1,2],"The entry scene must commit once, after its original animation")
            XCTAssertTrue(probe.revealedWhileOriginalSurfaceVisible)
            XCTAssertGreaterThan(try XCTUnwrap(probe.nextStateAt).timeIntervalSince(try XCTUnwrap(probe.started)),(fainted ? 2.2:3.2)+(shiny ? 1.05:0))
            if doubles { XCTAssertLessThan(try XCTUnwrap(probe.nextStateAt).timeIntervalSince(try XCTUnwrap(probe.started)),shiny ? 6.2:5,"A pair must play together, not sequentially") }
            XCTAssertEqual(recalls,[!fainted],"A fainted outgoing Pokémon must not receive the living recall animation")
            XCTAssertGreaterThan(gifs.count,1,"The actual GIF must keep advancing through the entry animation")
            XCTAssertEqual(sawSparkle,shiny)
            XCTAssertNil(player.error)
        }
    }
}
@MainActor private final class EntryQueueProbe {
    var scenes:[Int]=[];var started:Date?;var nextStateAt:Date?;var finished=false
    var revealedWhileOriginalSurfaceVisible=false
}
@MainActor private struct EntryQueueFixture:View {
    let player:PokeRogueBattlePlayer;let probe:EntryQueueProbe;let doubles:Bool;let fainted:Bool;let shiny:Bool
    @State private var events:[BattleVisualEvent]=[]
    @State private var busy=false
    @State private var playback:BattleEffectPlayback?
    private func pokemon(_ id:String,fainted:Bool=false)->BattleCombatant {
        BattleCombatant(id:id,speciesID:25,name:"Pikachu",level:50,shiny:shiny && id.hasPrefix("new"),active:true,form:nil,fainted:fainted,hp:fainted ? 0:100,maxHP:100,status:"",stats:nil)
    }
    var body:some View {
        let positions=(0..<(doubles ? 4:2)).map{BattleEffectPosition(own:$0%2==0,slot:$0/2)}
        let actors=positions.map{p in PokeRogueActor(pokemon:pokemon(p.key,fainted:fainted && p.key=="own-0"),position:p,rect:CGRect(x:p.own ? 40+p.slot*100:450+p.slot*50,y:p.own ? 160:30,width:100,height:110))}
        let field=BattleFieldState(weather:"",weatherSuppressed:false,conditions:[],ownSide:[],foeSide:[])
        let own=[pokemon("new")]+(doubles ? [pokemon("new-1")]:[])
        let foe=[pokemon("foe-0")]+(doubles ? [pokemon("foe-1")]:[])
        let scenes=Dictionary(uniqueKeysWithValues:(doubles ? [1,2,3]:[1,2]).map{($0,BattleScene(id:$0,turn:2,own:own,foe:foe,field:field))})
        Color.clear.modifier(PokeRogueBattlefieldLayers(player:player)).overlay{
            BattleEffectsLayer(events:events,rects:Dictionary(uniqueKeysWithValues:actors.map{($0.position.key,$0.rect)}),busy:$busy,playback:$playback,scenes:scenes,
                onScene:{scene in
                    probe.scenes.append(scene.id)
                    if scene.id==1{probe.revealedWhileOriginalSurfaceVisible=player.isPlaying}
                    if scene.id==(doubles ? 3:2){probe.nextStateAt=Date()}
                },onFinished:{probe.finished=true},originalPlayer:player,actors:actors,viewport:CGSize(width:doubles ? 680:660,height:310))
        }.frame(width:doubles ? 680:660,height:310)
        .task{
            try? await Task.sleep(for:.milliseconds(100));probe.started=Date()
            let source=BattleEffectPosition(own:true,slot:0)
            events=[BattleVisualEvent(id:1,move:"",type:"",category:"Status",source:source,targets:[],phase:"entry"),
                    BattleVisualEvent(id:2,move:"",type:"",category:"Status",source:doubles ? BattleEffectPosition(own:true,slot:1):source,targets:[],phase:doubles ? "entry":"state")]
            if doubles { events.append(BattleVisualEvent(id:3,move:"",type:"",category:"Status",source:source,targets:[],phase:"state")) }
        }
    }
}
