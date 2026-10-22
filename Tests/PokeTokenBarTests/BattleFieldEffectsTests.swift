import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class BattleFieldEffectsTests: XCTestCase {
    func testOpeningWeatherIsNotSkippedByInitialEffectCursor() async throws {
        let source=BattleEffectPosition(own:true,slot:0)
        let event=BattleVisualEvent(id:5,move:"commonrain",type:"",category:"Status",source:source,
            targets:[BattleEffectTarget(position:source,hit:true)],moveID:"commonrain",phase:"field")
        var started:[Int]=[]
        let host=NSHostingController(rootView:OpeningFieldFixture(event:event,onStart:{started.append($0)}))
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:640,height:300),styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentViewController=host;window.orderFront(nil)
        defer{window.orderOut(nil);window.contentViewController=nil}
        let deadline=Date().addingTimeInterval(3)
        while started.isEmpty && Date()<deadline{try await Task.sleep(for:.milliseconds(20))}
        XCTAssertEqual(started,[5],"Entry weather must play even when its scene exists before the window mounts")
    }
    func testPilotUsesActualWeatherAndFieldScenesWithoutDuplicatingTrickRoomMove() throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let process=Process(),output=Pipe()
        process.executableURL=root.appendingPathComponent("BattleEngine/runtime/node")
        process.arguments=[root.appendingPathComponent("BattleEngine/tests/fixtures/field-effects.cjs").path]
        process.standardOutput=output
        try process.run();let data=output.fileHandleForReading.readDataToEndOfFile();process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus,0)
        let frames=try JSONDecoder().decode([BattleFrame].self,from:data)
        var renderedKeys=Set<String>()
        for frame in frames {
            let events=BattlePresentationEvents(frame:frame,language:.en,ownPlayer:0)
            for effect in events.events where effect.phase=="field" {
                renderedKeys.insert(effect.moveID!)
                let global=BattleFieldEffects.weather.values.contains(effect.moveID!) || BattleFieldEffects.globalFields.contains(effect.moveID!)
                XCTAssertEqual(BattleFieldEffects.isGlobal(effect),global)
                let ordinary=BattleVisualEvent(id:effect.id,move:effect.move,type:effect.type,category:effect.category,source:effect.source,targets:effect.targets,moveID:effect.moveID)
                XCTAssertFalse(BattleFieldEffects.isGlobal(ordinary),"A normal move must not spread USER-focused particles across both teams")
                XCTAssertNotNil(PokeRogueOriginalCatalog.shared.entry(effect))
            }
            for scene in frame.scenes ?? [] {
                let line=frame.log[scene.id-(frame.logOffset ?? 0)]
                if line.hasPrefix("|-weather|"),line.contains("[from] ability:") {
                    XCTAssertEqual(events.events.first{$0.id==scene.id}?.phase,"field","Entry abilities must not consume the same scene as an ability-only notice")
                }
            }
        }
        XCTAssertTrue(Set(BattleFieldEffects.weather.values).isSubset(of:renderedKeys))
        XCTAssertTrue(BattleFieldEffects.fields.isSubset(of:renderedKeys))
        for language in AppLanguage.allCases {
            let rain=BattlePresentationEvents(frame:frames[0],language:language,ownPlayer:0)
            let weather=rain.events.filter{$0.phase=="field"}
            XCTAssertEqual(weather.count,2,"Original weather animation plays when weather starts and at upkeep")
            XCTAssertTrue(weather.allSatisfy{$0.moveID=="commonrain"})
            XCTAssertTrue(weather.allSatisfy{rain.messages[$0.id]?.contains(L(language).battleWeather("raindance"))==true})
            let room=BattlePresentationEvents(frame:frames[1],language:language,ownPlayer:0)
            let effects=room.events.filter{$0.moveID=="trickroom"}
            XCTAssertEqual(effects.count,1,"The move and field-start scene must share one original animation")
            let event=try XCTUnwrap(effects.first)
            XCTAssertEqual(event.phase,"field")
            XCTAssertTrue(try XCTUnwrap(frames[1].scenes?.first{$0.id==event.id}).field.conditions.contains("trickroom"))
            XCTAssertNotNil(PokeRogueOriginalCatalog.shared.entry(event))
        }
        let frame=frames[0],scene=try XCTUnwrap(frame.scenes?.first{!$0.field.weather.isEmpty})
        let suppressed=BattleFieldState(weather:scene.field.weather,weatherSuppressed:true,conditions:scene.field.conditions,ownSide:scene.field.ownSide,foeSide:scene.field.foeSide)
        let blocked=BattleScene(id:scene.id,turn:scene.turn,own:scene.own,foe:scene.foe,field:suppressed)
        XCTAssertNotNil(BattleFieldEffects.effect(scene:blocked,line:"|-weather|RainDance",frame:frame),"Suppression affects weather mechanics, not the weather itself")
        XCTAssertNil(BattleFieldEffects.effect(scene:scene,line:"|-weather|none",frame:frame))
        XCTAssertNil(BattleFieldEffects.effect(scene:scene,line:"|-fieldend|move: Trick Room",frame:frame))
        XCTAssertNil(BattleFieldEffects.effect(scene:scene,line:"|-sidestart|p1",frame:frame))
    }
}

@MainActor
private struct OpeningFieldFixture: View {
    let event: BattleVisualEvent
    let onStart: (Int)->Void
    @State private var busy=false
    @State private var playback: BattleEffectPlayback?
    var body: some View {
        BattleEffectsLayer(events:[event],rects:["own-0":CGRect(x:30,y:100,width:100,height:100)],busy:$busy,playback:$playback,
            presentOpeningAbilities:true,reducedMotionOverride:true)
            .frame(width:640,height:300)
            .onChange(of:playback?.event.id){_,id in if let id{onStart(id)}}
    }
}
