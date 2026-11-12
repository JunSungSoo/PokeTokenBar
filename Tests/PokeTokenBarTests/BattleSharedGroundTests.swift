import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
private final class GroundSnapshotBattle: BattleSessionPresentation {
    let identity = BattleIdentity(nickname: "지면 확인", code: "GROUND", nonce: "qa")
    let opponent: BattleIdentity? = .init(nickname: "상대", code: "OTHER", nonce: "qa")
    let presentation = BattleScenePlayback()
    let frame: BattleFrame?
    let phase = BattleCoordinator.Phase.playing
    let mode = BattleMode.doubles
    let arena = BattleArena.plains
    let registeredTeam: [BattlePokemon] = []
    let opponentRoster: [BattleRosterMember] = []
    let decisionDeadline: Date? = nil
    let submitted = false
    let outcome: String? = nil
    let error: String? = nil
    let isHost = true
    let isChallenge = true
    init(_ frame: BattleFrame) { self.frame = frame }
    func choose(_ decision: BattleDecision) {}
    func completePresentation() {}
    func connectManual(_ code: String) {}
}

@MainActor
final class BattleSharedGroundTests: XCTestCase {
    func testRealKnockoutWithoutReservesAndLargePairRenderOnCorrectGround() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let task = Process(), pipe = Pipe()
        task.executableURL = BattleEngineProcess.runtimeURL
        task.arguments = [root.appendingPathComponent("BattleEngine/tests/fixtures/shared-ground.cjs").path]
        task.standardOutput = pipe
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        XCTAssertEqual(task.terminationStatus, 0)
        let frames = try JSONDecoder().decode([String: BattleFrame].self, from: data)
        for name in ["large-pair", "survivor-0", "survivor-1"] {
            let frame = try XCTUnwrap(frames[name])
            let members = frame.own.filter(\.active)
            XCTAssertEqual(members.count, 2, "The engine retains the fainted active slot")
            let living = members.map { !$0.fainted }
            XCTAssertEqual(living.filter { $0 }.count, name == "large-pair" ? 2 : 1)
            XCTAssertFalse(frame.own.contains { !$0.active && !$0.fainted }, "No replacement can enter")
            if name != "large-pair" {
                let dead = try XCTUnwrap(members.firstIndex(where: \.fainted))
                XCTAssertTrue(frame.slots[dead].canPass)
                XCTAssertFalse(frame.slots[dead].mustSwitch)
            }
            for own in [false, true] {
                let widths = members.map { PokeRogueSpriteSizes.shared.battleSize(speciesID: $0.speciesID, form: $0.form, back: own).width }
                let layout = BattlePairGroundLayout(widths: widths, living: living, stageWidth: 189)
                let ground = try XCTUnwrap(layout.ground)
                XCTAssertGreaterThanOrEqual(ground.minX, 0)
                XCTAssertLessThanOrEqual(ground.maxX, layout.width)
                for slot in members.indices where living[slot] {
                    let center = 189 / 2.0 + CGFloat(slot) * (189 + layout.spacing)
                    XCTAssertLessThanOrEqual(ground.minX, center - widths[slot] / 2)
                    XCTAssertGreaterThanOrEqual(ground.maxX, center + widths[slot] / 2)
                }
                if name != "large-pair" {
                    let full = try XCTUnwrap(BattlePairGroundLayout(widths: widths, living: [true, true], stageWidth: 189).ground)
                    XCTAssertLessThan(ground.width, full.width)
                }
            }
            let suite = "SharedGround.\(UUID())", defaults = UserDefaults(suiteName: suite)!
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(suite + ".json")
            defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: file) }
            let store = CompanionStore(fileURL: file, defaults: defaults); store.setLanguage(.ko)
            let battle = GroundSnapshotBattle(frame)
            var measurement: BattleContentMeasurement?
            let host = NSHostingController(rootView: BattleView(battle: battle, store: store, onSurrender: {}, onMusic: {},
                onPlayMusic: {}, allowsEffectsAudio: false, replayOpening: false, onLayout: { measurement = $0 }).frame(width: 680))
            host.sizingOptions = []
            let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 680, height: 1000),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentViewController = host; window.orderFront(nil)
            defer { window.orderOut(nil); window.contentViewController = nil }
            try await Task.sleep(for: .milliseconds(900))
            let measured = try XCTUnwrap(measurement)
            XCTAssertLessThanOrEqual(try XCTUnwrap(measured.battlers).maxY, try XCTUnwrap(measured.battlefield).maxY + 0.5)
            window.setContentSize(NSSize(width: 680, height: measured.content.height))
            host.view.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
            host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: "/tmp/ptb-ground-\(name).png"))
        }
        XCTAssertNil(BattlePairGroundLayout(widths: [177, 177], living: [false, false], stageWidth: 189).ground)
        let widest = BattlePairGroundLayout(widths: [177, 177], living: [true, true], stageWidth: 189)
        XCTAssertEqual(widest.ground?.width, widest.width)
    }
}
