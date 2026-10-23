import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor final class BattleHealthTests:XCTestCase {
    private func pokemon(_ id:String,hp:Int=100,active:Bool=true,fainted:Bool=false,maxHP:Int=100)->BattleCombatant {
        BattleCombatant(id:id,speciesID:25,name:"Pikachu",level:50,shiny:false,active:active,form:nil,fainted:fainted,hp:hp,maxHP:maxHP,status:"",stats:nil)
    }
    private func frame(own:[BattleCombatant],foe:[BattleCombatant])->BattleFrame {
        BattleFrame(revision:"health",turn:2,decisionID:"health",preview:false,waiting:false,own:own,foe:foe,slots:[],log:[],effects:[],field:field,logOffset:0,scenes:[],ended:false,winner:nil)
    }
    private var field:BattleFieldState { .init(weather:"",weatherSuppressed:false,conditions:[],ownSide:[],foeSide:[]) }
    func testDamageAndHealingInterpolateBothSidesBeforeCommittingFaint() async throws {
        let state=BattleScenePlayback()
        let own=[pokemon("own",hp:20),pokemon("bench",hp:10,active:false)],foe=[pokemon("foe")]
        state.accept(frame(own:own,foe:foe))
        let target=BattleScene(id:1,turn:2,own:[pokemon("own",hp:80),pokemon("bench",hp:90,active:false)],foe:[pokemon("foe",hp:0,fainted:true)],field:field)
        var done=false,samples:[Int]=[],healing:[Int]=[]
        let started=Date(),task=Task{await state.animate(target);done=true}
        while !done {
            if let f=state.frame {
                samples.append(f.foe[0].hp);healing.append(f.own[0].hp)
                if f.foe[0].hp>0 {XCTAssertFalse(f.foe[0].fainted);XCTAssertEqual(f.own[1].hp,10)}
            }
            try await Task.sleep(for:.milliseconds(12))
        }
        await task.value
        XCTAssertTrue(samples.contains{$0>0 && $0<100});XCTAssertTrue(healing.contains{$0>20 && $0<80})
        XCTAssertEqual(samples,samples.sorted(by:>));XCTAssertEqual(healing,healing.sorted())
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started),0.75)
        XCTAssertEqual(state.frame?.foe[0].hp,0);XCTAssertTrue(state.frame!.foe[0].fainted)
        XCTAssertEqual(state.frame?.own[0].hp,80);XCTAssertEqual(state.frame?.own[1].hp,90)
    }
    func testReplacementMaxHPAndResetDoNotTweenUnrelatedPokemon() async throws {
        let state=BattleScenePlayback()
        let scene=BattleScene(id:1,turn:2,own:[pokemon("replacement",hp:10)],foe:[pokemon("foe",hp:200,maxHP:200)],field:field)
        await state.animate(scene);XCTAssertNil(state.frame)
        state.accept(frame(own:[pokemon("old")],foe:[pokemon("foe")]))
        await state.animate(scene)
        XCTAssertEqual(state.frame?.own[0].id,"replacement");XCTAssertEqual(state.frame?.foe[0].hp,200)
        state.reset();state.accept(frame(own:[pokemon("own")],foe:[pokemon("foe")]))
        let damage=BattleScene(id:2,turn:2,own:[pokemon("own")],foe:[pokemon("foe",hp:0,fainted:true)],field:field)
        let pending=Task{await state.animate(damage)}
        try await Task.sleep(for:.milliseconds(90));state.reset();await pending.value
        XCTAssertNil(state.frame,"An old HP animation must not resurrect a reset battle")
        state.accept(frame(own:[pokemon("own")],foe:[pokemon("foe")]))
        let cancelled=Task{await state.animate(damage)}
        try await Task.sleep(for:.milliseconds(90));cancelled.cancel();await cancelled.value
        XCTAssertGreaterThan(state.frame!.foe[0].hp,0)
    }
    func testDamageAmountsHiddenButCauseAndBattleNoticesRemainLocalized() throws {
        for language in AppLanguage.allCases {
            XCTAssertNil(BattleLogText.describe("|-damage|p2a: Pikachu|25/100",language:language))
            let status=try XCTUnwrap(BattleLogText.describe("|-damage|p2a: Pikachu|25/100 psn|[from] psn",language:language))
            XCTAssertFalse(status.contains("25/100"));XCTAssertTrue(status.contains(L(language).battleDamageCause("psn")))
            let ability=try XCTUnwrap(BattleLogText.describe("|-damage|p1a: Pikachu|25/100|[from] ability: Rough Skin",language:language))
            XCTAssertFalse(ability.contains("25/100"));XCTAssertTrue(ability.contains(BattleTextCatalog.shared.abilityName("Rough Skin",language:language)))
            let log=["|-crit|p2a: Pikachu","|-supereffective|p2a: Pikachu","|-resisted|p2a: Pikachu","|-damage|p2a: Pikachu|25/100"]
            let own=[pokemon("own")],foe=[pokemon("foe",hp:25)]
            let f=frame(own:own,foe:foe)
            let scenes=log.indices.map{BattleScene(id:$0,turn:2,own:own,foe:foe,field:field)}
            let full=BattleFrame(revision:f.revision,turn:f.turn,decisionID:f.decisionID,preview:false,waiting:false,own:own,foe:foe,slots:[],log:log,effects:[],field:field,logOffset:0,scenes:scenes,ended:false,winner:nil)
            let presentation=BattlePresentationEvents(frame:full,language:language,ownPlayer:0)
            for i in 0...2 {XCTAssertNotNil(presentation.messages[i])}
            XCTAssertNil(presentation.messages[3]);XCTAssertEqual(presentation.events.last?.phase,"health")
        }
    }
    func testSpreadDrainsTogetherButRepeatedHitsRemainSeparate() async throws {
        for spread in [true,false] {
            let state=BattleScenePlayback(),probe=HealthQueueProbe()
            let own=[pokemon("own")],foe=[pokemon("foe")]+(spread ? [pokemon("foe2")]:[])
            state.accept(frame(own:own,foe:foe))
            let first=BattleScene(id:2,turn:2,own:own,foe:[pokemon("foe",hp:50)]+(spread ? [pokemon("foe2")]:[]),field:field)
            let second=BattleScene(id:3,turn:2,own:own,foe:[pokemon("foe",hp:spread ? 50:25)]+(spread ? [pokemon("foe2",hp:50)]:[]),field:field)
            let host=NSHostingController(rootView:HealthQueueFixture(state:state,probe:probe,target:first,second:second))
            let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:660,height:310),styleMask:[.borderless],backing:.buffered,defer:false)
            window.contentViewController=host;window.orderFront(nil)
            defer{window.orderOut(nil);window.contentViewController=nil}
            let deadline=Date().addingTimeInterval(12)
            while !probe.finished,Date()<deadline {
                if spread {XCTAssertEqual(state.frame!.foe[0].hp,state.frame!.foe[1].hp,"Spread targets must drain concurrently")}
                try await Task.sleep(for:.milliseconds(15))
            }
            XCTAssertTrue(probe.finished)
            XCTAssertEqual(probe.healthSceneIDs,spread ? [3]:[2,3])
            XCTAssertEqual(probe.moveIDs,[1,4])
            XCTAssertEqual(probe.hpAtMove,[100,spread ? 50:25])
        }
    }
    func testSerializedEffectsWaitForHPDrainBeforeNextMove() async throws {
        let state=BattleScenePlayback(),probe=HealthQueueProbe()
        state.accept(frame(own:[pokemon("own")],foe:[pokemon("foe")]))
        let target=BattleScene(id:2,turn:2,own:[pokemon("own")],foe:[pokemon("foe",hp:25)],field:field)
        let host=NSHostingController(rootView:HealthQueueFixture(state:state,probe:probe,target:target))
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:660,height:310),styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentViewController=host;window.orderFront(nil)
        defer{window.orderOut(nil);window.contentViewController=nil}
        let deadline=Date().addingTimeInterval(12)
        var intermediate=false
        while !probe.finished,Date()<deadline {
            let hp=state.frame!.foe[0].hp
            if hp<100&&hp>25 {intermediate=true;XCTAssertEqual(probe.moveIDs,[1])}
            try await Task.sleep(for:.milliseconds(15))
        }
        XCTAssertTrue(probe.finished);XCTAssertTrue(intermediate)
        XCTAssertEqual(probe.moveIDs,[1,3]);XCTAssertEqual(probe.hpAtMove,[100,25])
    }
}
@MainActor private final class HealthQueueProbe {var finished=false;var moveIDs:[Int]=[];var hpAtMove:[Int]=[];var healthSceneIDs:[Int]=[]}
@MainActor private struct HealthQueueFixture:View {
    let state:BattleScenePlayback;let probe:HealthQueueProbe;let target:BattleScene
    var second:BattleScene?=nil
    @State private var events:[BattleVisualEvent]=[]
    @State private var busy=false
    @State private var playback:BattleEffectPlayback?
    var body:some View {
        BattleEffectsLayer(events:events,rects:[:],busy:$busy,playback:$playback,reducedMotionOverride:true,scenes:second.map{[2:target,3:$0]} ?? [2:target],
            onScene:{state.apply($0)},onFinished:{probe.finished=true},onAnimatedScene:{probe.healthSceneIDs.append($0.id);await state.animate($0)})
            .frame(width:660,height:310)
            .onChange(of:playback?.event.id){_,id in if let id{probe.moveIDs.append(id);probe.hpAtMove.append(state.frame!.foe[0].hp)}}
            .task {
                try? await Task.sleep(for:.milliseconds(100))
                let own=BattleEffectPosition(own:true,slot:0),foe=BattleEffectPosition(own:false,slot:0)
                events=[BattleVisualEvent(id:1,move:"Tackle",type:"normal",category:"Physical",source:own,targets:[.init(position:foe,hit:true)]),
                    BattleVisualEvent(id:2,move:"",type:"",category:"Status",source:foe,targets:[],phase:"health")]
                if let second { events.append(BattleVisualEvent(id:3,move:"",type:"",category:"Status",source:.init(own:false,slot:second.foe.count>1 ? 1:0),targets:[],phase:"health")) }
                events.append(BattleVisualEvent(id:second == nil ? 3:4,move:"Tackle",type:"normal",category:"Physical",source:foe,targets:[.init(position:own,hit:true)]))
            }
    }
}
