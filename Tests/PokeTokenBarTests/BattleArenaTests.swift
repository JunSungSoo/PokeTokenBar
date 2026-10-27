import AppKit
import CryptoKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor final class BattleArenaTests: XCTestCase {
    func testCuratedPoolContainsThreePerGroupAndEveryChoiceIsReachable() {
        XCTAssertEqual(BattleArena.allCases.count, 15)
        XCTAssertEqual(Dictionary(grouping: BattleArena.allCases, by: \.group).mapValues(\.count),
                       ["woods":3, "water":3, "highlands":3, "caves":3, "settlements":3])
        XCTAssertEqual(BattleArena.forMatch(""), .plains)
        let selections = (0..<1000).map { BattleArena.forMatch("match-\($0)") }
        XCTAssertEqual(Set(selections), Set(BattleArena.allCases))
        // Stable cross-process vectors guard order, salt and hash algorithm changes.
        XCTAssertEqual(BattleArena.forMatch("match-0").rawValue, "plains")
        XCTAssertEqual(BattleArena.forMatch("match-1").rawValue, "ice_cave")
        XCTAssertTrue((0..<20).allSatisfy { _ in BattleArena.forMatch("match-0") == selections[0] })
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
