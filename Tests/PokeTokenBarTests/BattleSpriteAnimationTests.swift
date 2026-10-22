import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import PokeTokenBar

private final class BattleAnimationURLProtocol: URLProtocol, @unchecked Sendable {
    final class State: @unchecked Sendable {
        let lock = NSLock()
        private var data: [String:Data] = [:]
        private var paths: [String] = []
        func configure(_ data: [String:Data]) { lock.withLock { self.data=data; paths=[] } }
        func reply(_ path: String) -> Data? { lock.withLock { paths.append(path); return data[path] } }
        var requests: [String] { lock.withLock { paths } }
    }
    static let state = State()
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "raw.githubusercontent.com" && request.url?.pathExtension == "gif"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url=request.url, let data=Self.state.reply(url.path) else {
            client?.urlProtocol(self,didFailWithError:URLError(.fileDoesNotExist)); return
        }
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:url,statusCode:200,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class BattleSpriteAnimationTests: XCTestCase {
    private func pixels(_ color: NSColor, rect: CGRect) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data:nil,width:64,height:64,bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(try XCTUnwrap(color.usingColorSpace(.deviceRGB)).cgColor)
        context.fill(rect)
        return try XCTUnwrap(context.makeImage())
    }
    private func fixture() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("battle-animation-\(UUID())")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        for back in [false,true] {
            let data = NSMutableData()
            let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data,UTType.gif.identifier as CFString,2,nil))
            for color in back ? [NSColor.blue,.yellow] : [NSColor.red,.green] {
                CGImageDestinationAddImage(destination,try pixels(color,rect:CGRect(x:12,y:12,width:40,height:40)),
                    [kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:0.12]] as CFDictionary)
            }
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            let key = SpriteStore.cacheKey(speciesID:25,animated:true,shiny:false,back:back)
            try (data as Data).write(to:directory.appendingPathComponent(key+".gif"))
            let png = NSBitmapImageRep(cgImage:try pixels(.gray,rect:CGRect(x:12,y:12,width:40,height:40)))
            try XCTUnwrap(png.representation(using:.png,properties:[:])).write(to:directory.appendingPathComponent(
                SpriteStore.cacheKey(speciesID:25,animated:false,shiny:false,back:back)+".png"))
        }
        return directory
    }
    private func pokemon(fainted: Bool = false) -> BattleCombatant {
        BattleCombatant(id:"sprite",speciesID:25,name:"Pikachu",level:37,shiny:false,active:true,
            form:nil,fainted:fainted,hp:fainted ? 0 : 100,maxHP:100,status:"",stats:nil)
    }
    private func sample<V: View>(_ root: V) async throws -> Set<String> {
        let host = NSHostingController(rootView:root)
        let window = NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:148,height:133),styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentViewController=host;window.setContentSize(NSSize(width:148,height:133));window.orderFront(nil)
        defer { window.orderOut(nil);window.contentViewController=nil }
        var colors = Set<String>()
        for _ in 0..<14 {
            try await Task.sleep(for:.milliseconds(40))
            host.view.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.view.bitmapImageRepForCachingDisplay(in:host.view.bounds))
            host.view.cacheDisplay(in:host.view.bounds,to:bitmap)
            let color = try XCTUnwrap(bitmap.colorAt(x:bitmap.pixelsWide/2,y:bitmap.pixelsHigh/2)?.usingColorSpace(.deviceRGB))
            // Display color management changes component values; compare distinct color families.
            let r=color.redComponent, g=color.greenComponent, b=color.blueComponent
            if r > 0.65 && g > 0.65 && b < 0.65 { colors.insert("yellow") }
            else if r > g + 0.15 && r > b + 0.15 { colors.insert("red") }
            else if g > r + 0.15 && g > b + 0.15 { colors.insert("green") }
            else if b > r + 0.15 && b > g + 0.15 { colors.insert("blue") }
            else { colors.insert("neutral") }
        }
        return colors
    }
    func testProductionStagesAdvanceFrontAndBackGIFsInBothBattleSizes() async throws {
        let directory = try fixture();defer { try? FileManager.default.removeItem(at:directory) }
        let store = SpriteStore(directory:directory)
        for back in [false,true] {
            for size: CGFloat in [100,128] {
                let colors = try await sample(BattlePokemonStage(pokemon:pokemon(),back:back,stageSize:size,spriteStore:store))
                XCTAssertTrue(colors.contains(back ? "blue" : "red"),"Correct facing must display its first GIF frame: \(colors)")
                XCTAssertTrue(colors.contains(back ? "yellow" : "green"),"The visible stage must advance beyond its first GIF frame: \(colors)")
            }
        }
    }
    func testColdStagesDownloadAndPlayTheirExactFacingGIF() async throws {
        let directory = try fixture();defer { try? FileManager.default.removeItem(at:directory) }
        var replies: [String:Data] = [:]
        for back in [false,true] {
            let file=directory.appendingPathComponent(SpriteStore.cacheKey(speciesID:25,animated:true,shiny:false,back:back)+".gif")
            replies[SpriteStore.spriteURL(speciesID:25,animated:true,shiny:false,back:back).path]=try Data(contentsOf:file)
            try FileManager.default.removeItem(at:file)
        }
        BattleAnimationURLProtocol.state.configure(replies)
        URLProtocol.registerClass(BattleAnimationURLProtocol.self)
        defer { URLProtocol.unregisterClass(BattleAnimationURLProtocol.self);BattleAnimationURLProtocol.state.configure([:]) }
        let store = SpriteStore(directory:directory)
        for back in [false,true] {
            let colors = try await sample(BattlePokemonStage(pokemon:pokemon(),back:back,stageSize:128,spriteStore:store))
            XCTAssertTrue(colors.contains(back ? "blue" : "red"))
            XCTAssertTrue(colors.contains(back ? "yellow" : "green"))
        }
        XCTAssertEqual(Set(BattleAnimationURLProtocol.state.requests),Set(replies.keys))
    }
    func testMotionDisabledAndFaintedSpritesRemainStatic() async throws {
        let directory = try fixture();defer { try? FileManager.default.removeItem(at:directory) }
        let store = SpriteStore(directory:directory)
        let disabled = try await sample(BattlePokemonStage(pokemon:pokemon(),back:false,stageSize:128,spriteStore:store,animated:false))
        XCTAssertEqual(disabled.count,1)
        let fainted = try await sample(BattlePokemonStage(pokemon:pokemon(fainted:true),back:true,stageSize:128,spriteStore:store))
        XCTAssertEqual(fainted.count,1)
    }
    func testSharedCropRetainsNativePoseMovementAndFrameDelays() throws {
        let frames = try [CGRect(x:5,y:9,width:20,height:35),CGRect(x:15,y:4,width:20,height:35)].enumerated().map { index, rect in
            (image:NSImage(cgImage:try pixels(.red,rect:rect),size:NSSize(width:64,height:64)),delay:Double(index+1)/10)
        }
        let cropped = BattleSpriteGeometry.croppedFrames(frames)
        XCTAssertEqual(cropped.map(\.image.size),[NSSize(width:30,height:40),NSSize(width:30,height:40)])
        XCTAssertEqual(cropped.map(\.delay),[0.1,0.2])
        let bounds = try cropped.map { try XCTUnwrap(BattleSpriteGeometry.contentBounds(XCTUnwrap(NSBitmapImageRep(data:XCTUnwrap($0.image.tiffRepresentation))))) }
        XCTAssertNotEqual(bounds[0].origin,bounds[1].origin,"Do not remove the native motion by cropping each pose separately")
        // In bitmap coordinates the second pose has twice the stance area and duration.
        // Its center is 20/30, the first is 10/30: a 4:1 weighted mean is 0.6.
        XCTAssertEqual(BattleSpriteGeometry.horizontalCenter(cropped),0.6,accuracy:0.0001)
    }
}
