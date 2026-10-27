import AppKit
import CryptoKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Matrix QA uses production arena/WebGL/notice layers, mounted outside all monitors.
/// The small native HUD is a labeled probe; full BattleView geometry is tested separately.
@MainActor final class BattleArenaVisualTests: XCTestCase {
    func testEveryArenaWithBackgroundMotionAndForegroundMovesInBothFormats() async throws {
        let player = PokeRogueBattlePlayer()
        let hud = NSView(), notice = NSView()
        let state = ArenaAuditState()
        let window = NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:680,height:410),styleMask:[.borderless],backing:.buffered,defer:false)
        let host = NSHostingController(rootView:ArenaAuditScene(player:player,state:state,hud:hud,notice:notice))
        window.contentViewController=host; window.orderFront(nil)
        defer { player.stop();window.orderOut(nil);window.contentViewController=nil }
        XCTAssertTrue(NSScreen.screens.allSatisfy { !$0.frame.intersects(window.frame) })
        await player.start()
        let deadline=Date().addingTimeInterval(20)
        while !player.ready, player.error == nil, Date()<deadline { try await Task.sleep(for:.milliseconds(25)) }
        XCTAssertTrue(player.ready,player.error ?? "Renderer timeout");guard player.ready else{return}
        let folder=ProcessInfo.processInfo.environment["PTB_ARENA_CAPTURE_DIR"].map{URL(fileURLWithPath:$0)}
        if let folder { try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true) }
        var report:[[String:Any]]=[]
        let sprite = try spritePayload()
        for mode in BattleMode.allCases {
            state.mode=mode
            for arena in BattleArena.allCases {
                state.arena=arena
                host.view.layoutSubtreeIfNeeded()
                try await Task.sleep(for:.milliseconds(25))
                XCTAssertTrue(isAbove(hud,player.backgroundWebView),"\(arena): background cannot cover native HUD/characters")
                XCTAssertTrue(isAbove(player.webView,hud),"\(arena): effects must stay above native HUD")
                XCTAssertTrue(isAbove(notice,player.webView),"\(arena): messages must stay above effects")
                let width=mode == .singles ? 660:680, height=mode == .singles ? 310:260
                let actors:[[String:Any]]=(0..<(mode == .singles ? 2:4)).map { i in
                    let own=i%2==0,slot=i/2
                    return ["key":BattleEffectPosition.key(own:own,slot:slot),"own":own,"slot":slot,"texture":"arena-audit-\(i)","sprite":sprite,
                            "x":own ? 105+slot*310:width-105-slot*310,"y":own ? height-20:125]
                }
                for move in ["closecombat","thunder","quickattack","surf"] {
                    for reverse in [false,true] {
                        state.move=move
                        let source=reverse ? "foe-0":"own-0"
                        let targets=(0..<(mode == .doubles && move == "surf" ? 2:1)).map { ["key":BattleEffectPosition.key(own:reverse,slot:$0)] }
                        let payload:[String:Any] = ["move":move,"actors":actors,"source":source,"targets":targets,"hit":true,"width":width,"height":height,"scale":1.5,"effectsVolume":0]
                        var captures:[String:NSImage]=[:]
                        for background in [true,false] {
                            let result=try await player.evaluate(Self.auditScript,arguments:["payload":payload],background:background)
                            XCTAssertEqual(result["errors"] as? [String],[],"\(arena)/\(mode)/\(move)/\(reverse)/\(background)")
                            XCTAssertTrue(result["finished"] as? Bool == true)
                            if move == "quickattack" && background { XCTAssertEqual(result["peak"] as? Int,0) }
                            if ["closecombat","thunder"].contains(move) && background { XCTAssertGreaterThan(result["peak"] as? Int ?? 0,100) }
                            if !background { XCTAssertGreaterThan(result["peak"] as? Int ?? 0,100,"Actors/effects must actually render") }
                            if let url=result["png"] as? String,let data=Data(base64Encoded:String(url.split(separator:",",maxSplits:1)[1])),let image=NSImage(data:data) {
                                captures[background ? "background":"foreground"]=image
                            }
                        }
                        report.append(["arena":arena.rawValue,"mode":mode.rawValue,"move":move,"reverse":reverse,"passed":true])
                        // Diagnostic contact sheets are composites of original WebGL captures and
                        // production SwiftUI arena/notices; HUD labels explicitly identify the probe.
                        if let folder,!reverse {
                            let image=try composite(arena:arena,mode:mode,move:move,layers:captures)
                            let bitmap=try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
                            try bitmap.representation(using:.png,properties:[:])?.write(to:folder.appendingPathComponent("\(mode.rawValue)-\(arena.rawValue)-\(move).png"))
                        }
                    }
                }
            }
        }
        XCTAssertEqual(report.count,240)
        if let folder { try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("matrix.json")) }
        XCTAssertNil(player.error)
    }

    private static let auditScript = """
    await window.ptbPrepare(payload);
    const errors=[], ranks={background:0,actor:1,effect:2};let peak=0,png='',finished=false;
    const sample=async()=>{
      const image=new Image();image.src=document.querySelector('canvas').toDataURL();await image.decode();
      const c=document.createElement('canvas');c.width=image.width;c.height=image.height;
      const ctx=c.getContext('2d');ctx.drawImage(image,0,0);const d=ctx.getImageData(0,0,c.width,c.height).data;
      let opaque=0;for(let i=3;i<d.length;i+=4)if(d[i])opaque++;
      return {opaque,png:image.src};
    };
    for(let time=50;time<=12000;time+=50){
      const advanced=window.ptbAdvance(50),state=window.ptbInspect();
      const order=state.layers.map(x=>ranks[x]).filter(x=>x!==undefined);
      if(order.some((x,i)=>i&&x<order[i-1]))errors.push('Invalid actor/effect depth at '+time);
      if(state.sprites.some(s=>![s.x,s.y,s.screenX,s.screenY].every(Number.isFinite)))errors.push('Invalid coordinates');
      if([250,750,1500,3000].includes(time)){
        const pixels=await sample();peak=Math.max(peak,pixels.opaque);
        // Composite the two WebGL surfaces at exactly the same source timestamp.
        if(time===750)png=pixels.png;
      }
      if(advanced.done){finished=true;break;}
    }
    window.ptbFinish();const cleared=await sample();if(cleared.opaque)errors.push('Residual effect pixels after finish');
    if(!png)png=cleared.png;
    return {errors,peak,png,finished};
    """

    private func spritePayload() throws -> [String:Any] {
        let url=PokeRogueOriginalCatalog.directory.appendingPathComponent("mega-sprites/6-mega-x.png")
        let image=try XCTUnwrap(NSImage(contentsOf:url))
        let bitmap=try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:64,pixelsHigh:64,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0))
        let context=try XCTUnwrap(NSGraphicsContext(bitmapImageRep:bitmap))
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context;context.imageInterpolation = .none
        let size=SpriteFit.size(for:image.size,box:64)
        image.draw(in:NSRect(x:(64-size.width)/2,y:0,width:size.width,height:size.height));NSGraphicsContext.restoreGraphicsState()
        let data=try XCTUnwrap(bitmap.representation(using:.png,properties:[:]))
        return ["frames":["data:image/png;base64,"+data.base64EncodedString()],"delays":[1]]
    }
    private func isAbove(_ top:NSView,_ bottom:NSView)->Bool {
        func path(_ view:NSView)->[NSView] { var result=[view];var current=view.superview;while let next=current {result.append(next);current=next.superview};return result.reversed() }
        let a=path(top),b=path(bottom)
        for i in 1..<min(a.count,b.count) where a[i] !== b[i] {
            guard a[i-1] === b[i-1],let ai=a[i-1].subviews.firstIndex(of:a[i]),let bi=b[i-1].subviews.firstIndex(of:b[i]) else{return false}
            return ai>bi
        };return false
    }
    private func composite(arena:BattleArena,mode:BattleMode,move:String,layers:[String:NSImage]) throws -> NSImage {
        let size=CGSize(width:mode == .singles ? 660:680,height:mode == .singles ? 310:260)
        let base=try XCTUnwrap(ImageRenderer(content:PokeRogueArena(arena:arena).frame(width:size.width,height:size.height).clipped()).nsImage)
        let notices=try XCTUnwrap(ImageRenderer(content:BattleNoticeStack(notices:[.init(id:1,text:"리자몽의 \(move)!",began:Date()),.init(id:2,text:"효과가 굉장했다!",began:Date())]).frame(width:size.width,height:size.height)).nsImage)
        let image=NSImage(size:size);image.lockFocus();defer{image.unlockFocus()}
        let rect=CGRect(origin:.zero,size:size)
        base.draw(in:rect);layers["background"]?.draw(in:rect)
        for own in [true,false] {
            let card=CGRect(x:own ? 235:size.width-365,y:own ? 35:size.height-100,width:220,height:65)
            NSColor(calibratedRed:0.97,green:0.97,blue:0.87,alpha:1).setFill();NSBezierPath(roundedRect:card,xRadius:6,yRadius:6).fill()
            ("HUD probe · HP 100 / 100" as NSString).draw(at:CGPoint(x:card.minX+10,y:card.minY+35),withAttributes:[.font:NSFont.systemFont(ofSize:13,weight:.semibold),.foregroundColor:NSColor.black])
            NSColor.systemGreen.setFill();NSBezierPath(roundedRect:CGRect(x:card.minX+10,y:card.minY+12,width:195,height:8),xRadius:4,yRadius:4).fill()
        }
        layers["foreground"]?.draw(in:rect);notices.draw(in:rect)
        return image
    }
}

@MainActor @Observable private final class ArenaAuditState {
    var arena=BattleArena.plains
    var mode=BattleMode.singles
    var move="thunder"
}
@MainActor private struct ArenaAuditScene:View {
    let player:PokeRogueBattlePlayer
    let state:ArenaAuditState
    let hud:NSView
    let notice:NSView
    var body:some View {
        let width:CGFloat=state.mode == .singles ? 660:680,height:CGFloat=state.mode == .singles ? 310:260
        VStack(spacing:0) {
            Text("Arena QA · \(state.arena.rawValue)").frame(width:width,height:40)
            ArenaAuditProbe(view:hud).frame(width:width,height:height)
                .modifier(PokeRogueBattlefieldLayers(player:player,arena:state.arena))
                .overlay {
                    BattleNoticeStack(notices:[.init(id:1,text:"리자몽의 \(state.move)!",began:Date())])
                        .overlay { ArenaAuditProbe(view:notice).frame(width:1,height:1) }
                }.clipped()
            Text("Command area · must remain clear").frame(width:width,height:40)
        }.frame(width:width)
    }
}
@MainActor private struct ArenaAuditProbe:NSViewRepresentable {
    let view:NSView
    func makeNSView(context:Context)->NSView {view}
    func updateNSView(_ view:NSView,context:Context) {}
}
