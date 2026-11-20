import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class BattleFieldSceneTests: XCTestCase {
    private func assertPoint(_ actual: CGPoint, _ expected: CGPoint, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 1e-9, message, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 1e-9, message, file: file, line: line)
    }

    func testOriginalFieldFitsTheBattlefieldHeightAndCropsBothSidesEqually() {
        let scene = BattleFieldScene(size: CGSize(width: 636, height: 351))
        let unit = 351.0 / 132
        XCTAssertEqual(scene.unit, unit, accuracy: 1e-9)
        XCTAssertEqual(scene.origin.x, (636 - 320 * unit) / 2, accuracy: 1e-9)
        XCTAssertEqual(scene.origin.y, 0)
        func field(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: scene.origin.x + x * unit, y: y * unit) }
        assertPoint(scene.feet(own: true, slot: 0, count: 1), field(106, 148), "PlayerPokemon feet")
        assertPoint(scene.feet(own: false, slot: 0, count: 1), field(236, 84), "EnemyPokemon feet")
        XCTAssertGreaterThan(scene.feet(own: true, slot: 0, count: 1).y, 351, "The original message box hides the player's feet")
        assertPoint(scene.feet(own: true, slot: 0, count: 2), field(74, 140), "Player LEFT")
        assertPoint(scene.feet(own: true, slot: 1, count: 2), field(138, 148), "Player RIGHT")
        assertPoint(scene.feet(own: false, slot: 0, count: 2), field(204, 76), "Enemy LEFT")
        assertPoint(scene.feet(own: false, slot: 1, count: 2), field(268, 84), "Enemy RIGHT")
        XCTAssertEqual(scene.baseRect(own: true), CGRect(x: scene.origin.x, y: 0, width: 320 * unit, height: 132 * unit))
        XCTAssertEqual(scene.baseRect(own: false), CGRect(x: scene.origin.x + 20 * unit, y: 0, width: 320 * unit, height: 132 * unit))
        XCTAssertEqual(scene.backgroundRect, CGRect(x: scene.origin.x, y: 0, width: 320 * unit, height: 180 * unit))
    }

    func testWiderFieldKeepsFeetOnTheirPlatformsAndStillCoversTheBackground() {
        let scene = BattleFieldScene(size: CGSize(width: 1200, height: 299))
        XCTAssertEqual(scene.unit, 299.0 / 132, accuracy: 1e-9)
        XCTAssertGreaterThan(scene.origin.x, 0)
        let background = scene.backgroundRect
        XCTAssertLessThanOrEqual(background.minX, 0)
        XCTAssertGreaterThanOrEqual(background.maxX, 1200)
        XCTAssertEqual(background.minY, 0)
        XCTAssertGreaterThanOrEqual(background.height, 299)
        XCTAssertEqual(background.midX, 600, accuracy: 1e-9)
    }

    func testStageBoxPutsFeetAtTheBottomAndCentreAtTheOriginalFocus() {
        for mode in BattleMode.allCases {
            let sizing = BattleSpriteSizing.forBattle(mode: mode, own: [], foe: [])
            let scene = BattleFieldScene(size: CGSize(width: BattleWindowLayout.preferredWidth(for: mode) - 24,
                                                      height: BattleSpriteSizing.battlefieldHeight(for: mode)))
            let count = mode == .doubles ? 2 : 1
            for own in [true, false] {
                for slot in 0..<count {
                    let feet = scene.feet(own: own, slot: slot, count: count)
                    let stage = scene.stageFrame(own: own, slot: slot, count: count, sizing: sizing)
                    XCTAssertEqual(stage.midX, feet.x, accuracy: 1e-9)
                    XCTAssertEqual(stage.maxY - BattleSpriteGeometry.footInset, feet.y, accuracy: 1e-9)
                    // battle-anims.ts focuses user/target 32 field units above the feet.
                    XCTAssertEqual(feet.y - stage.midY, 32 * sizing.pixelScale, accuracy: 1e-9)
                }
            }
        }
    }

    func testBattlersUseOneOriginalAtlasPixelPerFieldUnitInEitherMode() {
        for mode in BattleMode.allCases {
            let sizing = BattleSpriteSizing.forBattle(mode: mode, own: [], foe: [])
            XCTAssertEqual(sizing.pixelScale, BattleSpriteSizing.battlefieldHeight(for: mode) / 132, accuracy: 1e-9)
            XCTAssertEqual(BattleFieldScene(size: CGSize(width: 700, height: BattleSpriteSizing.battlefieldHeight(for: mode))).unit,
                           sizing.pixelScale, accuracy: 1e-9, "Sprites and platforms share one camera")
        }
        XCTAssertEqual(BattleSpriteSizing.forBattle(mode: .singles, own: [], foe: []).pixelScale, 351.0 / 132, accuracy: 1e-9)
        XCTAssertEqual(BattleSpriteSizing.forBattle(mode: .doubles, own: [], foe: []).pixelScale, 299.0 / 132, accuracy: 1e-9)
    }
}

@MainActor
final class BattleFieldScreenFocusTests: XCTestCase {
    func testEndPlatformPlaysItsAtlasInOriginalFilenameOrder() throws {
        // arena-base.ts plays generateFrameNames(start: 1, zeroPad: 4), not the JSON's packing order.
        for own in [true, false] {
            let layer = try XCTUnwrap(BattleArenaLayer.load(arena: .end, own: own))
            XCTAssertEqual(layer.frameNames, (1...16).map { String(format: "%04d.png", $0) })
            XCTAssertEqual(layer.frames.count, 16)
        }
        XCTAssertEqual(try XCTUnwrap(BattleArenaLayer.load(arena: .plains, own: true)).frames.count, 1)
    }

    func testScreenFocusGraphicsFollowTheCroppedArenaAndWidenOnlyLikeTheBackground() async throws {
        let player = PokeRogueBattlePlayer()
        let host = NSHostingController(rootView: Color.clear.frame(width: 636, height: 351).modifier(PokeRogueBattlefieldLayers(player: player)))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 636, height: 351), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentViewController = host; window.orderFront(nil)
        defer { player.stop(); window.orderOut(nil); window.contentViewController = nil }
        await player.start()
        let until = Date().addingTimeInterval(15)
        while !player.ready, player.error == nil, Date() < until { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertTrue(player.ready)
        for width in [636.0, 1400.0] {
            let scene = BattleFieldScene(size: CGSize(width: width, height: 351))
            // The move player's viewport is the battlefield in field units (points / scale).
            let mapped = try await player.evaluate("const core=await import('./player-core.js');return core.screenFocus(point,viewport)",
                arguments: ["point": ["x": 236, "y": 84, "scaleX": 1, "scaleY": 1],
                            "viewport": ["width": width / scene.unit, "height": 351 / scene.unit]])
            let background = scene.backgroundRect
            let screenScale = background.width / 320
            XCTAssertEqual((mapped["x"] as? Double ?? .nan) * scene.unit, background.minX + 236 * screenScale, accuracy: 0.5, "width \(width)")
            XCTAssertEqual((mapped["y"] as? Double ?? .nan) * scene.unit, 84 * screenScale, accuracy: 0.5, "width \(width)")
            XCTAssertEqual((mapped["scaleX"] as? Double ?? .nan) * scene.unit, screenScale, accuracy: 0.001)
            if width == 636 {
                XCTAssertEqual((mapped["x"] as? Double ?? .nan) * scene.unit, scene.feet(own: false, slot: 0, count: 1).x, accuracy: 0.5,
                               "SCREEN (236,84) is the enemy's feet, as in the original")
            }
        }
    }
}
