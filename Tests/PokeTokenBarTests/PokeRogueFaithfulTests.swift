import AppKit
import CryptoKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import PokeTokenBar

@MainActor final class PokeRogueFaithfulTests:XCTestCase {
    func testSourceHashesAndVerbatimExtractedPlayerAndUnfilteredTimelines() throws {
        let root=PokeRogueFaithfulPlayer.directory
        let manifest=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("manifest.json"))) as? [String:Any])
        for (path,hash) in try XCTUnwrap(manifest["originalSHA256"] as? [String:String]) {
            XCTAssertEqual(SHA256.hash(data:try Data(contentsOf:root.appendingPathComponent(path))).map{String(format:"%02x",$0)}.joined(),hash,path)
        }
        let original=try String(contentsOf:root.appendingPathComponent("original/battle-anims.ts"),encoding:.utf8)
        let adapter=try String(contentsOf:root.appendingPathComponent("adapter.ts"),encoding:.utf8)
        for (start,end) in [("export class AnimConfig","export const moveAnims"),("interface GraphicFrameData","export class CommonBattleAnim")] {
            let lo=try XCTUnwrap(original.range(of:start)),hi=try XCTUnwrap(original.range(of:end))
            XCTAssertTrue(adapter.contains(original[lo.lowerBound..<hi.lowerBound]),"The host must not approximate original animation commands")
        }
        for name in PokeRogueFaithfulPlayer.moves {
            XCTAssertFalse(try Data(contentsOf:root.appendingPathComponent("battle-anims/\(name).json")).isEmpty)
        }
    }
    func gifStore() throws -> (SpriteStore,URL) {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("faithful-gif-\(UUID())")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        for back in [false,true] {
            let data=NSMutableData(),dest=try XCTUnwrap(CGImageDestinationCreateWithData(data,UTType.gif.identifier as CFString,2,nil))
            for color in [NSColor.yellow,NSColor.orange] {
                let image=NSImage(size:NSSize(width:32,height:32));image.lockFocus();color.setFill();NSRect(x:4,y:3,width:24,height:26).fill();image.unlockFocus()
                CGImageDestinationAddImage(dest,try XCTUnwrap(image.cgImage(forProposedRect:nil,context:nil,hints:nil)),[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:0.1]] as CFDictionary)
            }
            XCTAssertTrue(CGImageDestinationFinalize(dest))
            try (data as Data).write(to:directory.appendingPathComponent(SpriteStore.cacheKey(speciesID:25,animated:true,shiny:false,back:back)+".gif"))
        }
        return (SpriteStore(directory:directory),directory)
    }
    func testSinglePanelKeepsCurrentBackgroundAndAppliesOneRateToTheEntireSourceTimeline() async throws {
        let (store,directory)=try gifStore();defer{try? FileManager.default.removeItem(at:directory)}
        let player=PokeRogueFaithfulPlayer(spriteStore:store,singlePanel:true)
        let host=NSHostingController(rootView:PokeRogueFaithfulSurface(player:player).frame(width:532,height:300))
        let window=NSWindow(contentRect:NSRect(x:30,y:30,width:532,height:300),styleMask:[.titled],backing:.buffered,defer:false)
        window.contentViewController=host;window.orderFront(nil)
        defer{player.stop();window.orderOut(nil);window.contentViewController=nil}
        await player.start()
        let deadline=Date().addingTimeInterval(15)
        while !player.ready && player.error == nil && Date()<deadline { try await Task.sleep(for:.milliseconds(30)) }
        XCTAssertTrue(player.ready,player.error ?? "Renderer timeout")
        guard player.ready else{return}
        _ = try await player.evaluate("return window.faithfulConfigure(config)",arguments:["config":["move":"thunderbolt","reverse":false,"rate":1,"sameLayout":false,"loop":false,"sound":false]])
        let raw=try await player.evaluate("return window.faithfulSeek(8)")
        let snapshot=try XCTUnwrap(raw as? [String:Any]),traces=try XCTUnwrap(snapshot["traces"] as? [[[String:Any]]])
        XCTAssertTrue(traces[0].contains{ $0["texture"] as? String == "current-battle-background" && $0["visible"] as? Bool == true })
        XCTAssertTrue(traces[0].filter{ $0["texture"] as? String == "PRAS- Black BG" }.allSatisfy{ $0["visible"] as? Bool == false },"Source background commands must not replace the requested fixed backdrop")
        let actors=try XCTUnwrap(snapshot["actors"] as? [[[String:Any]]])
        XCTAssertEqual(actors.count,1)
        XCTAssertEqual(actors[0][0]["x"] as? Double,61)
        var advances:[Double]=[]
        for rate in [1.0,0.5] {
            _ = try await player.evaluate("return window.faithfulConfigure(config)",arguments:["config":["move":"quick-attack","reverse":false,"rate":rate,"sameLayout":false,"loop":false,"sound":false]])
            let value=try await player.evaluate("const before=window.faithfulInspect().clock;for(let i=0;i<3;i++)window.faithfulRenderStep(100);return window.faithfulInspect().clock-before")
            advances.append(try XCTUnwrap(value as? Double))
        }
        XCTAssertEqual(advances[0],300,accuracy:0.01)
        XCTAssertEqual(advances[1],150,accuracy:0.01)
        let cleanup=try await player.evaluate("return window.faithfulSeek(25)")
        XCTAssertEqual((cleanup as? [String:Any])?["done"] as? [Bool],[true],"Original cleanup must restore the idle GIF after the move")
    }
    func testOriginalWebGLPlayerBothDirectionsMotionToneBackgroundSoundAndNativeGIFCadence() async throws {
        let (store,directory)=try gifStore();defer{try? FileManager.default.removeItem(at:directory)}
        let payload=try await PokeRogueFaithfulPlayer.spritePayload(back:true,store:store)
        XCTAssertEqual((payload["frames"] as? [String])?.count,2)
        XCTAssertEqual(payload["delays"] as? [Double],[0.1,0.1])
        let player=PokeRogueFaithfulPlayer(spriteStore:store)
        let host=NSHostingController(rootView:PokeRogueFaithfulSurface(player:player).frame(width:960,height:270))
        let window=NSWindow(contentRect:NSRect(x:30,y:30,width:960,height:270),styleMask:[.titled],backing:.buffered,defer:false)
        let policy=NSApp.activationPolicy();NSApp.setActivationPolicy(.regular)
        window.contentViewController=host;window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        defer{player.stop();window.orderOut(nil);window.contentViewController=nil;NSApp.setActivationPolicy(policy)}
        await player.start()
        let deadline=Date().addingTimeInterval(20)
        while !player.ready && player.error == nil && Date()<deadline { try await Task.sleep(for:.milliseconds(50)) }
        XCTAssertNil(player.error)
        guard player.ready else { let debug = try? await player.evaluate("return {url:location.href,state:document.readyState,phaser:typeof Phaser,resources:performance.getEntriesByType('resource').map(r=>({name:r.name,size:r.transferSize}))}");print("Renderer debug",debug as Any,player.status);XCTFail("Original Phaser renderer failed to initialize: \(player.error ?? "timeout")");return }
        var sawTone=false,sawMovement=false,sawBackground=false,sawGraphics=false
        for reverse in [false,true] {for move in PokeRogueFaithfulPlayer.moves {
            _ = try await player.evaluate("return window.faithfulConfigure(config)",arguments:["config":["move":move,"reverse":reverse,"rate":1,"sameLayout":true,"loop":false,"sound":false]])
            for frame in [0,3,8,12,17] {
                let rawSnapshot=try await player.evaluate("return window.faithfulSeek(frame)",arguments:["frame":frame])
                let snapshot=try XCTUnwrap(rawSnapshot as? [String:Any])
                if move == "thunderbolt" && !reverse && frame == 0 { try JSONSerialization.data(withJSONObject:snapshot,options:[.prettyPrinted]).write(to:URL(fileURLWithPath:"/tmp/ptb-faithful-trace.json")) }
                XCTAssertEqual(snapshot["equal"] as? Bool,true,"Reference/integration state: \(move), reverse=\(reverse), frame=\(frame)")
                let traces=try XCTUnwrap(snapshot["traces"] as? [[[String:Any]]])
                for object in traces[0] {
                    let key=object["texture"] as? String ?? ""
                    if key.hasPrefix("PRAS-"){sawGraphics=true}
                    if key=="PRAS- Black BG"{sawBackground=true}
                    if let tone=object["tone"] as? [Double],tone.contains(where:{$0 != 0}){sawTone=true}
                    if key=="pikachu-back",let x=object["x"] as? Double,abs(x-106)>2 {sawMovement=true}
                }
            }
        }}
        XCTAssertTrue(sawGraphics);XCTAssertTrue(sawBackground);XCTAssertTrue(sawTone,"Volt Switch tone");XCTAssertTrue(sawMovement,"Quick Attack movement")
        _ = try await player.evaluate("return window.faithfulConfigure(config)",arguments:["config":["move":"quick-attack","reverse":false,"rate":1,"sameLayout":false,"loop":false,"sound":false]])
        let rawDifferent=try await player.evaluate("return window.faithfulSeek(5)")
        let different=try XCTUnwrap(rawDifferent as? [String:Any]);XCTAssertEqual(different["equal"] as? Bool,false)
        let first=try await player.inspect()
        var second=try await player.inspect()
        let gifDeadline=Date().addingTimeInterval(2)
        while first["gifFrames"] as? [[Int]] == second["gifFrames"] as? [[Int]], Date()<gifDeadline {
            try await Task.sleep(for:.milliseconds(55));second=try await player.evaluate("return window.faithfulRenderStep()") as? [String:Any] ?? [:]
        }
        XCTAssertEqual(first["frame"] as? Int,second["frame"] as? Int,"Paused effect stays on its selected frame")
        XCTAssertNotEqual(first["gifFrames"] as? [[Int]],second["gifFrames"] as? [[Int]],"GIF cadence continues during effect pause")
        _ = try await player.evaluate("return window.faithfulConfigure(config)",arguments:["config":["move":"thunderbolt","reverse":false,"rate":1,"sameLayout":true,"loop":false,"sound":true]])
        _ = try await player.evaluate("return window.faithfulSeek(3)")
        XCTAssertNil(player.error)
    }
}
