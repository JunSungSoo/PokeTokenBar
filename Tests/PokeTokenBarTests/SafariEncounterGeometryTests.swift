import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class SafariEncounterGeometryTests: XCTestCase {
    private func image() throws -> Data {
        // Deliberately asymmetric canvas: its visible stance is right of center and
        // has transparent space below it. The old square fitting misaligned both.
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:80,pixelsHigh:90,
            bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0))
        for y in 0..<90 { for x in 0..<80 { bitmap.setColor((x >= 42 && x < 62 && y >= 15 && y < 65) || (x >= 8 && x < 12 && y >= 15 && y < 25) ? NSColor(deviceRed:1,green:0,blue:1,alpha:1):NSColor(deviceRed:0,green:0,blue:0,alpha:0),atX:x,y:y) } }
        return try XCTUnwrap(bitmap.representation(using:.png,properties:[:]))
    }
    func testEncounterFootprintUsesSpeciesSizeAndFixedCamera() {
        let small = SafariEncounterGeometry(speciesID:25), large = SafariEncounterGeometry(speciesID:249)
        XCTAssertGreaterThan(large.spriteSize.height,small.spriteSize.height)
        XCTAssertGreaterThan(large.groundSize.width,small.groundSize.width)
        for id in 1...649 {
            let layout = SafariEncounterGeometry(speciesID:id)
            XCTAssertEqual(layout.groundSize.height,22)
            XCTAssertLessThanOrEqual(layout.spriteSize.height,SafariEncounterGeometry.slotHeight)
            XCTAssertLessThanOrEqual(layout.groundSize.width,SafariEncounterGeometry.slotWidth)
            XCTAssertGreaterThanOrEqual(layout.groundSize.width,layout.spriteSize.width)
            XCTAssertGreaterThanOrEqual(SafariEncounterGeometry.groundY-layout.spriteSize.height,0)
        }
    }
    func testProductionSpriteStanceCentersOnGroundAfterTransparentCrop() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let store = SpriteStore(directory:directory)
        let data = try image()
        for id in [25,109,130,249,321] {
            try data.write(to:directory.appendingPathComponent(SpriteStore.cacheKey(speciesID:id,animated:false,shiny:false,form:nil,back:false)+".png"))
            let species = SafariSpecies(id:id,area:.plains,types:["normal"],bst:500,legendary:false,captureRate:45)
            let wild = SafariPokemon(species:species,profile:.generate(seed:1),nature:.hardy,shiny:false)
            let renderer = ImageRenderer(content:SafariEncounterSprite(wild:wild,spriteStore:store))
            renderer.scale = 2
            let bitmap = NSBitmapImageRep(cgImage:try XCTUnwrap(renderer.cgImage))
            var minX=bitmap.pixelsWide,maxX = -1,maxY = -1,minY=bitmap.pixelsHigh
            for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
                if (bitmap.colorAt(x:x,y:y)?.alphaComponent ?? 0) > 0.5 {
                    minY=min(minY,y);maxY=max(maxY,y)
                }
            } }
            if maxY >= minY {
                for y in (maxY-(maxY-minY)/5)...maxY { for x in 0..<bitmap.pixelsWide {
                    if (bitmap.colorAt(x:x,y:y)?.alphaComponent ?? 0) > 0.5 { minX=min(minX,x);maxX=max(maxX,x) }
                } }
            }
            XCTAssertGreaterThan(maxX,minX,"Real sprite must render, not a placeholder")
            XCTAssertEqual(Double(minX+maxX+1)/4,Double(SafariEncounterGeometry.slotWidth/2),accuracy:1)
            let bottom = Double(maxY+1)/2
            XCTAssertGreaterThanOrEqual(bottom,Double(SafariEncounterGeometry.slotHeight)-3.5)
            XCTAssertLessThanOrEqual(bottom,Double(SafariEncounterGeometry.slotHeight)+0.5)
        }
    }
}
