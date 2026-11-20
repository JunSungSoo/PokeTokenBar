import AppKit
import CryptoKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor final class BattleArenaTests: XCTestCase {
    func testEveryTypeUsesFixedOriginalArenaAndMixedTiesIgnoreTeamOrder() {
        XCTAssertEqual(BattleArena.allCases.count,16)
        XCTAssertEqual(Set(BattleArena.typeArenas.keys),Set(BattleArena.typeOrder))
        for type in BattleArena.typeOrder {
            XCTAssertEqual(BattleArena.forTypes([type]),BattleArena.typeArenas[type])
            XCTAssertEqual(BattleArena.forTypes([type,type,"unknown"]),BattleArena.typeArenas[type])
        }
        XCTAssertEqual(BattleArena.forTypes([]),.plains)
        XCTAssertEqual(BattleArena.forTypes(["unknown"]),.plains)
        XCTAssertEqual(BattleArena.forTypes(["fire","flying","fire","water"]),.volcano)
        XCTAssertEqual(BattleArena.forTypes(["water","fire"]),.volcano)
        XCTAssertEqual(BattleArena.forTypes(["fire","water"]),.volcano)
    }
    func testAllChallengeArenasFollowFixedOpponentRostersIncludingDualTypes()throws {
        let catalog=try ChallengeEncounterCatalog.load()
        let arenas=Dictionary(uniqueKeysWithValues:catalog.encounters.map{($0.id,BattleArena.forOpponent($0.team.map(BattleRosterMember.init)))})
        XCTAssertEqual(arenas["brock"],.mountain)
        XCTAssertEqual(arenas["falkner"],.mountain)
        XCTAssertEqual(arenas["misty"],.lake)
        XCTAssertEqual(arenas["bugsy"],.forest)
        XCTAssertEqual(arenas["blaine"],.volcano)
        for encounter in catalog.encounters {
            XCTAssertEqual(BattleArena.forOpponent(encounter.team.reversed().map(BattleRosterMember.init)),arenas[encounter.id])
        }
    }

    func testOnlyRedOverridesTypeArenaWithOriginalEternatusEndBackground()throws {
        let encounters=try ChallengeEncounterCatalog.load().encounters
        for e in encounters {
            let roster=e.team.map(BattleRosterMember.init)
            XCTAssertEqual(BattleArena.forChallenge(encounterID:e.id,roster:roster),e.id=="red" ? .end:BattleArena.forOpponent(roster))
        }
        XCTAssertFalse(BattleArena.typeArenas.values.contains(.end))
        XCTAssertEqual(BattleArena.forChallenge(encounterID:"red",roster:[]),.end)
        XCTAssertEqual(BattleArena.end.backgroundPath,"images/arenas/end_bg.png")
    }
    func testEveryArenaDrawsBothOriginalPlatformsAtTheirFieldPositions() throws {
        let directory = PokeRogueOriginalCatalog.directory
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("manifest.json"))) as? [String:Any])
        let hashes = try XCTUnwrap(manifest["sha256"] as? [String:String])
        let size = CGSize(width: 636, height: 351)
        let scene = BattleFieldScene(size: size)
        for arena in BattleArena.allCases {
            let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(ImageRenderer(content: PokeRogueArena(arena: arena)
                .frame(width: size.width, height: size.height)).cgImage))
            // Sample each platform's leftmost outline pixel so a misplaced layer lands on background instead.
            for (own, row) in [(true, 131), (false, 74)] {
                let path = arena.platformPath(own: own)
                let data = try Data(contentsOf: directory.appendingPathComponent(path))
                XCTAssertEqual(SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined(), hashes[path], path)
                let frames = try XCTUnwrap(BattleArenaLayer.load(arena: arena, own: own)?.frames, path).map(NSBitmapImageRep.init(cgImage:))
                XCTAssertTrue(frames.allSatisfy { $0.pixelsWide == 320 && $0.pixelsHigh == 132 }, path)
                let first = try XCTUnwrap(frames.first)
                let column = try XCTUnwrap((0..<first.pixelsWide).first { (first.colorAt(x: $0, y: row)?.alphaComponent ?? 0) > 0.99 }, path)
                let base = scene.baseRect(own: own)
                let drawn = try XCTUnwrap(bitmap.colorAt(x: Int(base.minX + (CGFloat(column) + 0.5) * scene.unit),
                                                         y: Int(base.minY + (CGFloat(row) + 0.5) * scene.unit))?.usingColorSpace(.deviceRGB))
                // Animated platforms may be on any frame when rendered.
                let matches = try frames.contains { frame in
                    let original = try XCTUnwrap(frame.colorAt(x: column, y: row)?.usingColorSpace(.deviceRGB))
                    return original.alphaComponent > 0.99 && abs(drawn.redComponent - original.redComponent) < 0.04
                        && abs(drawn.greenComponent - original.greenComponent) < 0.04 && abs(drawn.blueComponent - original.blueComponent) < 0.04
                }
                XCTAssertTrue(matches, "\(path): drawn \(drawn) is not the platform outline")
            }
        }
    }
    func testSafariStandsOnEachAreaCroppedEnemyPlatform() throws {
        let stage = CGSize(width: 320, height: 160)
        for arena in BattleArena.allCases {
            let platform = try XCTUnwrap(BattleArenaPlatform.load(arena: arena), "\(arena)")
            XCTAssertLessThan(platform.size.width, 160 * BattleArenaPlatform.pointsPerPixel, "\(arena): cropped to the platform, not the 320px field")
            let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(ImageRenderer(content: ZStack(alignment: .bottom) {
                BattleArenaPlatformSurface(platform: platform)
            }.frame(width: stage.width, height: stage.height, alignment: .bottom)).cgImage))
            let foot = (x: Int(stage.width / 2), y: Int(stage.height - BattleSpriteGeometry.footInset))
            XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: foot.x, y: foot.y)).alphaComponent, 0.99, "\(arena): feet stand on the platform")
            XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 1, y: 1)).alphaComponent, 0.01, "\(arena): only the platform is drawn")
            XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: foot.x, y: foot.y - 60)).alphaComponent, 0.01, "\(arena): platform is centred on the feet")
            let opaqueColumns = (0..<bitmap.pixelsWide).filter { (bitmap.colorAt(x: $0, y: foot.y)?.alphaComponent ?? 0) > 0.99 }
            let ellipseCenter = (Double(try XCTUnwrap(opaqueColumns.first)) + Double(try XCTUnwrap(opaqueColumns.last)) + 1) / 2
            XCTAssertEqual(ellipseCenter, Double(stage.width / 2), accuracy: 4, "\(arena): platform is centred under the feet")
        }
    }
    func testBundledOriginalsMatchManifestAndCoverBothBattleSizes() throws {
        let directory = PokeRogueOriginalCatalog.directory
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("manifest.json"))) as? [String:Any])
        let hashes = try XCTUnwrap(manifest["sha256"] as? [String:String])
        let groups = try XCTUnwrap(manifest["arenas"] as? [String:[String]])
        XCTAssertEqual(groups, Dictionary(grouping: BattleArena.allCases, by: \.group).mapValues { $0.map(\.rawValue) })
        for arena in BattleArena.allCases {
            let data = try Data(contentsOf: directory.appendingPathComponent(arena.backgroundPath))
            XCTAssertEqual(SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined(), hashes[arena.backgroundPath])
            let original = try XCTUnwrap(NSBitmapImageRep(data:data))
            XCTAssertEqual(original.pixelsWide,320); XCTAssertEqual(original.pixelsHigh,180)
            for size in [CGSize(width:660,height:310), CGSize(width:680,height:260)] {
                let renderer = ImageRenderer(content:PokeRogueArena(arena:arena).frame(width:size.width,height:size.height).clipped())
                let image = try XCTUnwrap(renderer.nsImage)
                let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
                XCTAssertEqual(bitmap.pixelsWide,Int(size.width)); XCTAssertEqual(bitmap.pixelsHigh,Int(size.height))
                for (x,y) in [(0,0),(bitmap.pixelsWide-1,bitmap.pixelsHigh-1),(bitmap.pixelsWide/2,bitmap.pixelsHigh/2)] {
                    XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x:x,y:y)).alphaComponent,0.99,"\(arena): background must fill the viewport")
                }
            }
        }
    }
}
