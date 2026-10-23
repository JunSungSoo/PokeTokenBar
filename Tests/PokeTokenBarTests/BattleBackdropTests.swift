import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Render production WebGL in a borderless window outside every physical display.
@MainActor final class BattleBackdropTests:XCTestCase {
    func testTimedBackgroundPixelsAreIndependentOfPokemonCamera() async throws {
        let (store,directory)=try PokeRogueFaithfulTests().gifStore()
        defer{try? FileManager.default.removeItem(at:directory)}
        let player=PokeRogueBattlePlayer(spriteStore:store)
        let host=NSHostingController(rootView:Color.clear.frame(width:680,height:340).modifier(PokeRogueBattlefieldLayers(player:player)))
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:680,height:340),styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentViewController=host;window.setFrameOrigin(NSPoint(x:-10000,y:-10000));window.orderFront(nil)
        defer{player.stop();window.orderOut(nil);window.contentViewController=nil}
        XCTAssertFalse(NSScreen.screens.contains{$0.frame.intersects(window.frame)},"Validation must never appear on a monitor")
        await player.start()
        let deadline=Date().addingTimeInterval(20)
        while !player.ready,player.error==nil,Date()<deadline{try await Task.sleep(for:.milliseconds(25))}
        XCTAssertTrue(player.ready,player.error ?? "Renderer timeout")
        guard player.ready else{return}
        let sprite=try await PokeRogueFaithfulPlayer.spritePayload(back:true,store:store)
        _ = try await player.evaluate("window.backdropFixture=sprite;return {}",arguments:["sprite":sprite],background:true)
        let manifest=PokeRogueOriginalCatalog.shared.manifest
        let entries=manifest.entries.merging(manifest.fieldEntries ?? [:]){first,_ in first}
        let keys=try entries.keys.sorted().filter { key in
            try String(contentsOf:PokeRogueOriginalCatalog.directory.appendingPathComponent(entries[key]!.file),encoding:.utf8).contains("AnimTimedAddBgEvent")
        }
        XCTAssertGreaterThan(keys.count,100,"Audit every timed-background timeline")
        var failures:[String]=[],visible=0
        var captures:[String:String]=[:]
        for start in stride(from:0,to:keys.count,by:2) {
            let result=try await player.evaluate("""
            const capture=async()=>{
                const image=new Image();image.src=document.querySelector('canvas').toDataURL();await image.decode();
                const c=document.createElement('canvas');c.width=image.width;c.height=image.height;
                const ctx=c.getContext('2d');ctx.drawImage(image,0,0);return ctx.getImageData(0,0,c.width,c.height).data;
            };
            const manifest=await fetch('manifest.json').then(r=>r.json());
            const failures=[],captures={};let visible=0;
            for(const move of keys)for(const reverse of [false,true])for(const width of [660,680]){
                const height=width===680?260:310;
                const entry=manifest.entries[move]??manifest.fieldEntries[move];
                const raw=await fetch(entry.file).then(r=>r.json()),variants=Array.isArray(raw)?raw:[raw];
                const definition=variants[reverse&&variants.length>1?1:0];
                const events=Object.values(definition.frameTimedEvents).flat();
                const times=[...new Set([100,250,500,750,1000,...events.filter(e=>e.eventType==='AnimTimedAddBgEvent'||e.opacity>0).map(e=>e.frameIndex*50+Math.max(50,e.duration*25))])].sort((a,b)=>a-b);
                const frames=[];
                for(const scale of [1.5,.65]){
                    await window.ptbPrepare({move,actors:[{key:'own-0',own:true,slot:0,texture:'bg-test',sprite:window.backdropFixture,x:120,y:298},{key:'foe-0',own:false,slot:0,texture:'bg-test',sprite:window.backdropFixture,x:520,y:168}],source:reverse?'foe-0':'own-0',targets:[{key:reverse?'own-0':'foe-0'}],hit:true,width,height,scale,effectsVolume:0});
                    const samples=[];
                    let previous=0;
                    for(const time of times){
                        window.ptbAdvance(time-previous);previous=time;
                        const state=window.ptbInspect();
                        if(state.sprites.some(s=>![s.x,s.y,s.screenX,s.screenY].every(Number.isFinite)))failures.push(move+': invalid sprite geometry');
                        samples.push(await capture());
                        if(width===660&&['closecombat','thunder'].includes(move)&&time===250)captures[move+"-"+reverse+"-"+scale]=document.querySelector("canvas").toDataURL();
                    }
                    frames.push(samples);window.ptbFinish();
                }
                for(let i=0;i<frames[0].length;i++){
                    const a=frames[0][i],b=frames[1][i];let different=0,opaque=0;
                    // Nearest-neighbour WebGL sampling can shift an edge by one pixel after
                    // Float32 matrix multiplication. Compare that neighbourhood, not exact bytes.
                    const diff=(p,q)=>Math.abs(a[p]-b[q])+Math.abs(a[p+1]-b[q+1])+Math.abs(a[p+2]-b[q+2])+Math.abs(a[p+3]-b[q+3]);
                    for(let y=1;y<height-1;y+=2)for(let x=1;x<width-1;x+=2){
                        const p=(y*width+x)*4;if(a[p+3])opaque++;
                        if(diff(p,p)<=8)continue;
                        let match=false;
                        for(let dy=-1;dy<=1&&!match;dy++)for(let dx=-1;dx<=1;dx++)if(diff(p,((y+dy)*width+x+dx)*4)<=8){match=true;break;}
                        if(!match)different++;
                    }
                    if(opaque>100)visible++;
                    if(different>100)failures.push(move+'/'+reverse+'/'+width+'/'+i+': '+different+' camera-dependent background pixels');
                }
            }
            return {failures,visible,captures};
            """,arguments:["keys":Array(keys[start..<min(start+2,keys.count)])],background:true)
            failures += result["failures"] as? [String] ?? ["Invalid audit result"]
            visible += result["visible"] as? Int ?? 0
            captures.merge(result["captures"] as? [String:String] ?? [:]){_,last in last}
        }
        if let path=ProcessInfo.processInfo.environment["PTB_BACKGROUND_CAPTURE_DIR"] {
            let folder=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            for (name,url) in captures {
                let bytes=try XCTUnwrap(Data(base64Encoded:String(url.split(separator:",",maxSplits:1)[1])))
                try bytes.write(to:folder.appendingPathComponent(name+".png"))
            }
        }
        XCTAssertGreaterThan(visible,100,"The audit must actually render backgrounds")
        XCTAssertEqual(failures,[])
        let phases=try await player.evaluate("""
        const errors=[];
        for(const move of ['closecombat','thunder','confusion','psychic','psybeam','hydrocannon','silverwind','earthquake','gravity'])for(const reverse of [false,true]){
            await window.ptbPrepare({move,actors:[{key:'own-0',own:true,slot:0,texture:'bg-test',sprite:window.backdropFixture,x:120,y:298},{key:'foe-0',own:false,slot:0,texture:'bg-test',sprite:window.backdropFixture,x:520,y:168}],source:reverse?'foe-0':'own-0',targets:[{key:reverse?'own-0':'foe-0'}],hit:true,width:680,height:310,scale:.65,effectsVolume:0});
            let previous=0,peak=0,rises=0,falls=0,finished=false;
            for(let time=25;time<=10000;time+=25){
                window.ptbAdvance(25);const state=window.ptbInspect();
                const alpha=Math.max(0,...state.backdrops.filter(b=>b.visible).map(b=>b.alpha));
                if(alpha>previous+.001)rises++;
                if(alpha<previous-.001)falls++;
                peak=Math.max(peak,alpha);previous=alpha;
                if(move==='thunder'&&time===1000&&alpha<.99)errors.push(move+': scrolling erased the fade-in');
                if(state.done){finished=true;break;}
            }
            if(peak<.8||rises<3||falls<3||!finished)errors.push(move+'/'+reverse+': '+JSON.stringify({peak,rises,falls,finished}));
            window.ptbFinish();
            const image=new Image();image.src=document.querySelector('canvas').toDataURL();await image.decode();
            const canvas=document.createElement('canvas');canvas.width=image.width;canvas.height=image.height;
            const context=canvas.getContext('2d');context.drawImage(image,0,0);const pixels=context.getImageData(0,0,canvas.width,canvas.height).data;
            for(let i=3;i<pixels.length;i+=4)if(pixels[i]){errors.push(move+': residual background after cleanup');break;}
        }
        return {errors};
        """,background:true)
        XCTAssertEqual(phases["errors"] as? [String],[],"Moving backgrounds must fade in, stay visible and fade out before restoring the arena")
    }
}
