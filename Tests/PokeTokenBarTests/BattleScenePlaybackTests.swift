import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class BattleScenePlaybackTests: XCTestCase {
    private struct Match: Decodable {
        let initial: [BattleFrame]
        let resolved: [BattleFrame]
        let replaced: [BattleFrame]
        let ended: [BattleFrame]
    }
    private func matches() throws -> [String: Match] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let process = Process(), output = Pipe(), errors = Pipe()
        process.executableURL = root.appendingPathComponent("BattleEngine/runtime/node")
        process.arguments = [root.appendingPathComponent("BattleEngine/tests/fixtures/action-scenes.cjs").path]
        process.standardOutput = output; process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        return try JSONDecoder().decode([String: Match].self, from: data)
    }
    func testRealBothPerspectiveFramesHoldHPAndRequestsUntilPresentationCompletes() throws {
        for match in try matches().values {
            for player in [0, 1] {
                let state = BattleScenePlayback(), initial = match.initial[player], resolved = match.resolved[player]
                state.accept(initial)
                state.accept(resolved)
                XCTAssertTrue(state.pending)
                XCTAssertEqual(state.frame?.foe[0].hp, initial.foe[0].hp)
                XCTAssertEqual(state.frame?.own[0].hp, initial.own[0].hp)
                XCTAssertEqual(state.frame?.decisionID, initial.decisionID)
                // A repeated network frame must not replace the displayed moment.
                state.accept(resolved)
                XCTAssertTrue(state.pending)
                let first = (resolved.scenes ?? []).first { $0.id > (initial.scenes?.last?.id ?? -1) }!
                state.apply(first)
                XCTAssertEqual(state.frame?.own[0].hp, first.own[0].hp)
                XCTAssertFalse(state.frame!.ended)
                state.finish()
                XCTAssertFalse(state.pending)
                XCTAssertEqual(state.frame?.decisionID, resolved.decisionID)
                state.accept(match.replaced[player])
                XCTAssertEqual(state.frame?.own.map(\.id), resolved.own.map(\.id), "Incoming species/order must wait for its switch event")
                for scene in match.replaced[player].scenes ?? [] where scene.id > (resolved.scenes?.last?.id ?? -1) { state.apply(scene) }
                state.finish()
                XCTAssertEqual(state.frame?.own.map(\.id), match.replaced[player].own.map(\.id))
                state.accept(match.ended[player])
                XCTAssertTrue(state.pending)
                XCTAssertFalse(state.frame!.ended, "A winner must not replace the final attack/effect")
                state.finish()
                XCTAssertTrue(state.frame!.ended)
                state.reset()
                XCTAssertNil(state.frame); XCTAssertFalse(state.pending)
                state.accept(initial); state.accept(initial)
                XCTAssertFalse(state.pending, "Initial/reconnected state must not replay old turns")
            }
        }
    }
    func testMountedRealTurnAppliesHPOnlyAfterItsEffectThenPromptsReplacement() async throws {
        let match = try XCTUnwrap(matches()["doubles"])
        let state = BattleScenePlayback(), probe = SceneProbe()
        state.accept(match.initial[0])
        let host = NSHostingController(rootView: SceneFixture(state: state, next: match.resolved[0], probe: probe))
        let window = NSWindow(contentRect: NSRect(x:-10000,y:-10000,width:640,height:300), styleMask:[.borderless], backing:.buffered, defer:false)
        window.contentViewController = host; window.orderFront(nil)
        defer { window.orderOut(nil); window.contentViewController = nil }
        let deadline = Date().addingTimeInterval(22)
        while !probe.finished && Date() < deadline { try await Task.sleep(for:.milliseconds(25)) }
        XCTAssertTrue(probe.finished)
        XCTAssertEqual(probe.moves.count, 2, "Both actual attacks must play; knocked-out opponents cannot execute their selected moves")
        XCTAssertEqual(probe.moves[0].hp, [100,100], "The first animation must start with both foes unharmed")
        XCTAssertEqual(probe.moves[1].hp.filter { $0 == 0 }.count, 1, "Only the first target is fainted when the second animation begins")
        let damage = probe.applied.filter { $0.hp.contains(0) }
        XCTAssertFalse(damage.isEmpty)
        let firstDamage = try XCTUnwrap(damage.first)
        XCTAssertGreaterThanOrEqual(firstDamage.date.timeIntervalSince(probe.moves[0].date), 1.35, "HP cannot fall during the reduced-motion effect's 1.4-second playback")
        XCTAssertTrue(probe.applied.contains { $0.attackStage == 1 }, "The real Moxie boost must apply through its ability notice scene")
        XCTAssertEqual(state.frame?.decisionID, match.resolved[0].decisionID)
        XCTAssertTrue(state.frame!.foe.allSatisfy { $0.fainted })
        XCTAssertTrue(match.resolved[1].slots.allSatisfy(\.mustSwitch))
        XCTAssertTrue(probe.moves.allSatisfy { $0.pending }, "No next-turn commands/results can be shown while animations play")
    }
    func testMountedSwitchWaitsForTransitionAndNeverShowsTheFinalDamagedSpeciesEarly() async throws {
        let match = try XCTUnwrap(matches()["singles"]), state = BattleScenePlayback(), probe = SceneProbe()
        state.accept(match.resolved[1])
        let oldID = state.frame!.own.first(where: \.active)!.id
        let host = NSHostingController(rootView: SceneFixture(state:state,next:match.replaced[1],probe:probe))
        let window = NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:640,height:300),styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentViewController=host;window.orderFront(nil)
        defer { window.orderOut(nil);window.contentViewController=nil }
        try await Task.sleep(for:.milliseconds(350))
        XCTAssertEqual(state.frame!.own.first(where: \.active)!.id,oldID)
        let deadline=Date().addingTimeInterval(5)
        while !probe.finished && Date()<deadline { try await Task.sleep(for:.milliseconds(25)) }
        XCTAssertTrue(probe.finished)
        XCTAssertNotEqual(state.frame!.own.first(where: \.active)!.id,oldID)
        XCTAssertEqual(state.frame!.own.first(where: \.active)!.hp,40)
    }
}

@MainActor
private final class SceneProbe {
    var moves: [(date:Date,hp:[Int],pending:Bool)] = []
    var applied: [(date:Date,hp:[Int],attackStage:Int)] = []
    var finished = false
}
@MainActor
private struct SceneFixture: View {
    let state: BattleScenePlayback
    let next: BattleFrame
    let probe: SceneProbe
    @State private var shown: BattleFrame?
    @State private var busy = false
    @State private var playback: BattleEffectPlayback?
    var body: some View {
        let frame=shown ?? state.frame!
        let presentation=BattlePresentationEvents(frame:frame,language:.ko,ownPlayer:0)
        ZStack {
            Color.black
            BattleEffectsLayer(events:presentation.events,rects:["own-0":CGRect(x:30,y:175,width:100,height:100),"foe-0":CGRect(x:490,y:10,width:100,height:100)],busy:$busy,playback:$playback,messages:presentation.messages,reducedMotionOverride:true,
                scenes:Dictionary(uniqueKeysWithValues:(frame.scenes ?? []).map { ($0.id,$0) }),
                onScene:{ scene in
                    state.apply(scene)
                    probe.applied.append((Date(),state.frame!.foe.map(\.hp),state.frame!.own[0].boosts?["atk"] ?? 0))
                },onFinished:{ state.finish();probe.finished=true })
        }.frame(width:640,height:300)
            .onChange(of:playback?.event.id) { _,id in
                if id != nil { probe.moves.append((Date(),state.frame!.foe.map(\.hp),state.pending)) }
            }
            .task { try? await Task.sleep(for:.milliseconds(100));state.accept(next);shown=next }
    }
}
