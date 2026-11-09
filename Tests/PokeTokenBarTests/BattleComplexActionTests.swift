import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class BattleComplexActionTests: XCTestCase {
    struct Match: Decodable { let initial:[BattleFrame];let resolved:[BattleFrame] }
    func fixtures() throws -> [String:Match] {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let child=Process(),output=Pipe();child.executableURL=root.appendingPathComponent("BattleEngine/runtime/node")
        child.arguments=[root.appendingPathComponent("BattleEngine/tests/fixtures/complex-actions.cjs").path];child.standardOutput=output
        try child.run();let data=output.fileHandleForReading.readDataToEndOfFile();child.waitUntilExit()
        XCTAssertEqual(child.terminationStatus,0)
        return try JSONDecoder().decode([String:Match].self,from:data)
    }
    func testRealHealthEventsOnlyBatchExplicitSpreadDamageAndGiveRepeatedStrikesFeedback() throws {
        for (key,match) in try fixtures() {
            for player in [0,1] {
                let frame=match.resolved[player],last=match.initial[player].scenes?.last?.id ?? -1
                let p=BattlePresentationEvents(frame:frame,language:.ko,ownPlayer:player)
                let events=p.events.filter{$0.id>last}
                let health=events.filter{["health","hit"].contains($0.phase ?? "")}
                if key.hasSuffix("-multi") {
                    let hits=health.filter{$0.source.own == (player==1) && $0.source.slot==0}
                    XCTAssertEqual(hits.count,5)
                    XCTAssertEqual(hits.map(\.phase),["health","hit","hit","hit","hit"])
                    XCTAssertTrue(hits.allSatisfy{$0.healthGroup==nil})
                }
                if key.hasSuffix("-drain") || key.hasSuffix("-recoil") {
                    XCTAssertGreaterThanOrEqual(health.count,2)
                    XCTAssertFalse(BattleHealthEffects.canBatch(health[0],health[1]),key)
                }
                if key.hasSuffix("-spread"),key.hasPrefix("doubles") {
                    let grouped=health.filter{$0.healthGroup != nil}
                    XCTAssertGreaterThanOrEqual(grouped.count,2)
                    XCTAssertEqual(Set(grouped.compactMap(\.healthGroup)).count,1)
                }
                if key.hasSuffix("-guard") {
                    XCTAssertTrue(health.isEmpty)
                    XCTAssertTrue(events.contains{$0.phase=="guard"})
                }
                if key.hasSuffix("-residual") {
                    XCTAssertTrue(events.contains{$0.phase=="weather-hit"})
                    XCTAssertTrue(events.contains{$0.phase=="status"})
                    XCTAssertTrue(health.allSatisfy{$0.healthGroup==nil})
                }
                XCTAssertEqual(events.map(\.id),events.map(\.id).sorted())
            }
        }
    }
    func testRepeatedHitUsesOriginalCommonFeedbackAndEffectsVolume() async throws {
        let (store,directory)=try PokeRogueFaithfulTests().gifStore()
        defer{try? FileManager.default.removeItem(at:directory)}
        let player=PokeRogueBattlePlayer(spriteStore:store);player.setEffectsVolume(0)
        let host=NSHostingController(rootView:Color.clear.modifier(PokeRogueBattlefieldLayers(player:player)).frame(width:660,height:300))
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:660,height:300),styleMask:[.borderless],backing:.buffered,defer:false)
        XCTAssertTrue(NSScreen.screens.allSatisfy{!$0.frame.intersects(window.frame)})
        window.contentViewController=host;window.orderFront(nil)
        defer{player.stop();window.orderOut(nil);window.contentViewController=nil}
        let pokemon=BattleCombatant(id:"foe",speciesID:25,name:"Pikachu",level:50,shiny:false,active:true,form:nil,fainted:false,hp:50,maxHP:100,status:"",stats:nil)
        let position=BattleEffectPosition(own:false,slot:0)
        let event=BattleVisualEvent(id:1,move:"hit",type:"",category:"Status",source:position,targets:[.init(position:position,hit:true)],phase:"hit")
        let actor=PokeRogueActor(pokemon:pokemon,position:position,rect:CGRect(x:450,y:20,width:120,height:120))
        let task=Task{await player.play(event,actors:[actor],size:CGSize(width:660,height:300))}
        var observed=false
        let deadline=Date().addingTimeInterval(20)
        while Date()<deadline {
            if player.isPlaying {
                let inspection=try await player.inspect()
                if let feedback=inspection["weatherHit"] as? [String:Any] {
                    observed=true;XCTAssertEqual(feedback["source"] as? String,position.key)
                    let sounds=try XCTUnwrap(inspection["soundEvents"] as? [[String:Any]])
                    XCTAssertEqual(sounds.count,1)
                    XCTAssertEqual(sounds.first?["volume"] as? Double,0)
                }
            }
            if observed && !player.isPlaying {break}
            try await Task.sleep(for:.milliseconds(20))
        }
        let completed=await task.value
        XCTAssertTrue(completed,player.error ?? "Hit playback failed");XCTAssertTrue(observed)
        XCTAssertFalse(player.hidesNative(position));XCTAssertNil(player.error)
        XCTAssertEqual(BattleEffectPlayback.animationDuration(event),0.5)
    }
    func testMountedRealComplexTurnsFinishEachHPChangeBeforeTheNextAction() async throws {
        let matches=try fixtures()
        for kind in ["drain","recoil","multi","guard","knockout","residual","residualKO"] {
            let match=try XCTUnwrap(matches["singles-"+kind]),state=BattleScenePlayback(),probe=ComplexQueueProbe()
            state.accept(match.initial[0]);state.accept(match.resolved[0])
            let host=NSHostingController(rootView:ComplexQueueFixture(state:state,initial:match.initial[0],next:match.resolved[0],probe:probe))
            let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:660,height:300),styleMask:[.borderless],backing:.buffered,defer:false)
            XCTAssertTrue(NSScreen.screens.allSatisfy{!$0.frame.intersects(window.frame)})
            window.contentViewController=host;window.orderFront(nil)
            defer{window.orderOut(nil);window.contentViewController=nil}
            let deadline=Date().addingTimeInterval(70)
            while !probe.finished,Date()<deadline {try await Task.sleep(for:.milliseconds(25))}
            XCTAssertTrue(probe.finished,kind);XCTAssertFalse(probe.overlapped,kind)
            let p=BattlePresentationEvents(frame:match.resolved[0],language:.ko,ownPlayer:0)
            let last=match.initial[0].scenes?.last?.id ?? -1
            let expected=p.events.filter{$0.id>last}
            XCTAssertEqual(probe.started.map(\.id),expected.map(\.id),kind)
            var previous=match.initial[0]
            let scenes=Dictionary(uniqueKeysWithValues:(match.resolved[0].scenes ?? []).map{($0.id,$0)})
            for start in probe.started {
                XCTAssertEqual(start.ownHP,previous.own.map(\.hp),"\(kind): HP advanced before event \(start.id)")
                XCTAssertEqual(start.foeHP,previous.foe.map(\.hp),"\(kind): HP advanced before event \(start.id)")
                if let scene=scenes[start.id] {
                    previous=BattleFrame(revision:previous.revision,turn:scene.turn,decisionID:previous.decisionID,preview:false,waiting:false,
                        own:scene.own,foe:scene.foe,slots:[],log:[],ended:false,winner:nil)
                }
            }
            XCTAssertEqual(state.frame?.own.map(\.hp),match.resolved[0].own.map(\.hp))
            XCTAssertEqual(state.frame?.foe.map(\.hp),match.resolved[0].foe.map(\.hp))
            if kind=="multi" {XCTAssertEqual(probe.feedbackCount,4)}
        }
    }
}
@MainActor private final class ComplexQueueProbe {
    struct Start { let id:Int;let ownHP:[Int];let foeHP:[Int] }
    var started:[Start]=[];var finished=false;var animating=false;var overlapped=false;var feedbackCount=0
}
@MainActor private struct ComplexQueueFixture:View {
    let state:BattleScenePlayback;let initial:BattleFrame;let next:BattleFrame;let probe:ComplexQueueProbe
    @State private var events:[BattleVisualEvent]=[]
    @State private var busy=false
    var body:some View {
        let p=BattlePresentationEvents(frame:next,language:.ko,ownPlayer:0)
        BattleEffectsLayer(events:events,rects:[:],busy:$busy,messages:p.messages,reducedMotionOverride:true,
            scenes:Dictionary(uniqueKeysWithValues:(next.scenes ?? []).map{($0.id,$0)}),
            onScene:{state.apply($0)},onFinished:{state.finish();probe.finished=true},
            onAnimatedScene:{scene in probe.animating=true;await state.animate(scene);probe.animating=false},
            beforeEvent:{event in
                probe.overlapped = probe.overlapped || probe.animating
                probe.started.append(.init(id:event.id,ownHP:state.frame!.own.map(\.hp),foeHP:state.frame!.foe.map(\.hp)))
                if event.phase=="hit"{probe.feedbackCount+=1}
            })
            .frame(width:660,height:300)
            .task {try? await Task.sleep(for:.milliseconds(50));events=p.events.filter{$0.id>(initial.scenes?.last?.id ?? -1)}}
    }
}
