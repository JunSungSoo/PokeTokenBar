import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor final class PokeRogueOriginalPlayerTests:XCTestCase {
    private func actors(doubles:Bool=false)->[PokeRogueActor] {
        (0..<(doubles ? 4:2)).map { i in
            let own=i%2==0,slot=i/2
            return PokeRogueActor(pokemon:BattleCombatant(id:"p\(i)",speciesID:25,name:"Pikachu",level:50,shiny:false,active:true,form:nil,fainted:false,hp:100,maxHP:100,status:"",stats:nil),position:BattleEffectPosition(own:own,slot:slot),rect:CGRect(x:own ? 50+slot*100:450+slot*100,y:own ? 170:40,width:140,height:144))
        }
    }
    private func event(_ move:String,reverse:Bool=false,doubles:Bool=false,hit:Bool=true,phase:String?=nil)->BattleVisualEvent {
        BattleVisualEvent(id:1,move:move,type:"electric",category:"special",source:BattleEffectPosition(own:!reverse,slot:0),targets:(0..<(doubles ? 2:1)).map{BattleEffectTarget(position:BattleEffectPosition(own:reverse,slot:$0),hit:hit)},moveID:move,phase:phase)
    }
    private func wait(_ condition:()->Bool,seconds:Double=20) async throws {
        let end=Date().addingTimeInterval(seconds)
        while !condition(),Date()<end{try await Task.sleep(for:.milliseconds(25))}
        XCTAssertTrue(condition(),"Original production renderer timed out")
    }
    func testOriginalSoundEventsPlayOnceForSpreadTargetsWithLiveIndependentVolume() async throws {
        let (store,directory)=try PokeRogueFaithfulTests().gifStore()
        defer { try? FileManager.default.removeItem(at:directory) }
        let player=PokeRogueBattlePlayer(spriteStore:store)
        let host=NSHostingController(rootView:Color.clear.frame(width:800,height:320).modifier(PokeRogueBattlefieldLayers(player:player)))
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:800,height:320),styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentViewController=host;window.orderFront(nil)
        defer { player.stop();window.orderOut(nil);window.contentViewController=nil }
        await player.start();try await wait({player.ready || player.error != nil});XCTAssertNil(player.error)
        let sprite=try await PokeRogueFaithfulPlayer.spritePayload(back:true,store:store)
        let prepare="""
        const manifest=await fetch('manifest.json').then(r=>r.json());
        const definition=await fetch(manifest.entries.surf.file).then(r=>r.json());
        const config=Array.isArray(definition)?definition[0]:definition;
        const expected=Object.values(config.frameTimedEvents).flat().filter(e=>e.eventType==='AnimTimedSoundEvent'&&e.resourceName).length;
        await window.ptbPrepare({move:'surf',actors:[true,false,true,false].map((own,i)=>({key:(own?'own-':'foe-')+Math.floor(i/2),own,slot:Math.floor(i/2),texture:'sound-test',sprite,x:own?120:520,y:own?298:168})),source:'own-0',targets:[{key:'foe-0'},{key:'foe-1'}],hit:true,width:800,height:320,scale:2});
        window.ptbAdvance(120000);
        return {...window.ptbInspect(),expected};
        """
        for volume in [0.6,0,0.2] {
            player.setEffectsVolume(volume)
            let background=try await player.evaluate(prepare,arguments:["sprite":sprite],background:true)
            let foreground=try await player.evaluate(prepare,arguments:["sprite":sprite])
            XCTAssertEqual(background["effectsVolume"] as? Double,0)
            XCTAssertEqual((background["soundEvents"] as? [[String:Any]])?.count,0)
            let sounds=try XCTUnwrap(foreground["soundEvents"] as? [[String:Any]])
            let expected=try XCTUnwrap(foreground["expected"] as? Int)
            XCTAssertGreaterThan(expected,0)
            XCTAssertEqual(sounds.count,expected,"A spread move must not replay its shared sound for each target")
            XCTAssertEqual(try XCTUnwrap(foreground["effectsVolume"] as? Double),volume,accuracy:0.000001)
            XCTAssertEqual(foreground["audioState"] as? String,"running")
            XCTAssertGreaterThan(foreground["playingSounds"] as? Int ?? 0,0,"The real sound manager must play decoded sounds, not just record metadata")
            XCTAssertTrue(sounds.allSatisfy{($0["volume"] as? Double ?? -1)>=0 && ($0["volume"] as? Double ?? 2)<=volume+0.000001})
            if volume==0 { XCTAssertTrue(sounds.allSatisfy{($0["volume"] as? Double)==0}) }
            player.setEffectsVolume(0)
            var muted=try await player.inspect()
            let deadline=Date().addingTimeInterval(1)
            while (muted["effectsVolume"] as? Double) != 0 && Date()<deadline {
                try await Task.sleep(for:.milliseconds(10));muted=try await player.inspect()
            }
            XCTAssertEqual(muted["effectsVolume"] as? Double,0,"The running sound manager must update without waiting for the next move")
            for background in [false,true] {
                let stopped=try await player.evaluate("window.ptbFinish();return window.ptbInspect();",background:background)
                XCTAssertEqual(stopped["playingSounds"] as? Int,0)
                XCTAssertEqual(stopped["soundInstances"] as? Int,0,"Completed/cancelled moves must release all sound instances")
            }
        }
    }
    func testProductionLayersPlaceNativeHUDOverBackgroundAndParticlesOverActors() async throws {
        let (store,directory)=try PokeRogueFaithfulTests().gifStore();defer{try? FileManager.default.removeItem(at:directory)}
        let player=PokeRogueBattlePlayer(spriteStore:store),hud=NSView()
        hud.wantsLayer=true;hud.layer?.backgroundColor=NSColor.blue.cgColor
        let host=NSHostingController(rootView:BattleLayerHUDProbe(view:hud).frame(width:800,height:320).modifier(PokeRogueBattlefieldLayers(player:player)))
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:800,height:320),styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentViewController=host;window.orderFront(nil)
        defer{player.stop();window.orderOut(nil);window.contentViewController=nil}
        await player.start();try await wait({player.ready || player.error != nil});XCTAssertNil(player.error)
        host.view.layoutSubtreeIfNeeded()
        func path(_ view:NSView)->[NSView]{var result=[view];var current=view.superview;while let next=current{result.append(next);current=next.superview};return result.reversed()}
        func isAbove(_ top:NSView,_ bottom:NSView)->Bool{
            let a=path(top),b=path(bottom)
            for i in 1..<min(a.count,b.count) where a[i] !== b[i] {
                guard a[i-1] === b[i-1],let ai=a[i-1].subviews.firstIndex(of:a[i]),let bi=b[i-1].subviews.firstIndex(of:b[i]) else{return false}
                return ai>bi
            };return false
        }
        XCTAssertTrue(isAbove(hud,player.backgroundWebView),"Timed backgrounds must remain below native HP cards")
        XCTAssertTrue(isAbove(player.webView,hud),"The actual production foreground WebView must cover native HP cards")
        let sprite=try await PokeRogueFaithfulPlayer.spritePayload(back:true,store:store)
        let script="""
        return await window.ptbPrepare({move,actors:[{key:'own-0',own:true,slot:0,texture:'layer-test',sprite,x:120,y:298},{key:'foe-0',own:false,slot:0,texture:'layer-test',sprite,x:520,y:168}],source:move==='lick'?'foe-0':'own-0',targets:[{key:move==='lick'?'own-0':'foe-0'}],hit:true,width:800,height:320,scale:2});
        """
        let sample="""
        const image=new Image();image.src=document.querySelector('canvas').toDataURL();await image.decode();
        const canvas=document.createElement('canvas');canvas.width=image.width;canvas.height=image.height;
        const ctx=canvas.getContext('2d');ctx.drawImage(image,0,0);const data=ctx.getImageData(0,0,canvas.width,canvas.height).data;
        let opaque=0;for(let i=3;i<data.length;i+=4)if(data[i]>0)opaque++;
        return {opaque,total:canvas.width*canvas.height};
        """
        for move in ["quickattack","thunderbolt","surf","muddywater","sludgewave","aeroblast","lick"] {
            for background in [true,false]{_ = try await player.evaluate(script,arguments:["sprite":sprite,"move":move],background:background)}
            var sawParticle=false,sawBackdrop=false,sawTimedForeground=false
            for _ in 0..<(move=="aeroblast" ? 84:18) {
                for background in [true,false]{_ = try await player.evaluate("return window.ptbAdvance(50)",background:background)}
                let state=try await player.inspect(),ranks=["background":0,"actor":1,"effect":2]
                let layers=try XCTUnwrap(state["layers"] as? [String])
                XCTAssertEqual(layers.compactMap{ranks[$0]},layers.compactMap{ranks[$0]}.sorted(),"Particles must stay above source USER/TARGET sprites after every original depth command")
                sawParticle = sawParticle || layers.contains("effect")
                for backdrop in state["backdrops"] as? [[String:Any]] ?? [] {
                    let name=backdrop["resource"] as? String ?? ""
                    if name.contains(" FG") || name=="PRAS- Sketch + Lick" {
                        XCTAssertEqual(backdrop["layer"] as? String,"effect",name+" is an effect despite using an original background event")
                        sawTimedForeground=true
                    }
                }
                if move=="thunderbolt",!sawBackdrop,(state["backdrops"] as? [[String:Any]] ?? []).contains(where:{$0["visible"] as? Bool==true && ($0["alpha"] as? Double ?? 0)>0}){
                    let back=try await player.evaluate(sample,background:true),front=try await player.evaluate(sample)
                    XCTAssertGreaterThan(back["opaque"] as? Int ?? 0,0)
                    XCTAssertLessThan(front["opaque"] as? Int ?? 0,(front["total"] as? Int ?? 0)/2,"Opaque source background must never paint over HUD from the foreground surface")
                    sawBackdrop=true
                }
            }
            let foreground=try await player.evaluate(sample),background=try await player.evaluate(sample,background:true)
            if move=="quickattack" {
                XCTAssertGreaterThan(foreground["opaque"] as? Int ?? 0,0,"Source Pokémon/move pixels belong in front")
                XCTAssertEqual(background["opaque"] as? Int,0,"No Pokémon or impact pixels may leak into the background surface")
            }else if move=="thunderbolt"{XCTAssertTrue(sawBackdrop);XCTAssertTrue(sawParticle)}
            else {
                XCTAssertTrue(sawTimedForeground,move)
                if ["surf","muddywater","sludgewave","lick"].contains(move) {
                    XCTAssertEqual(background["opaque"] as? Int,0,"Timed foreground waves must never render behind the HUD")
                }
                if move=="surf"{XCTAssertGreaterThan(foreground["opaque"] as? Int ?? 0,40000,"The actual wave must paint over native HUD/actor pixels in the foreground")}
            }
            for background in [true,false] {
                _ = try await player.evaluate("return window.ptbFinish()",background:background)
                let cleared=try await player.evaluate(sample,background:background)
                XCTAssertEqual(cleared["opaque"] as? Int,0,"Both surfaces must clear before the next action")
            }
        }
    }
    func testEveryOriginalTimelineExecutesAllCommandsInProductionWebGL() async throws {
        let (store,directory)=try PokeRogueFaithfulTests().gifStore();defer{try? FileManager.default.removeItem(at:directory)}
        let player=PokeRogueBattlePlayer(spriteStore:store)
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:800,height:320),styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentView=player.webView;window.orderFront(nil)
        defer{player.stop();window.orderOut(nil);window.contentView=nil}
        await player.start();try await wait({player.ready || player.error != nil})
        XCTAssertNil(player.error);guard player.ready else{return}
        let sprite=try await PokeRogueFaithfulPlayer.spritePayload(back:true,store:store)
        _ = try await player.evaluate("window.auditSprite=sprite;return {}",arguments:["sprite":sprite])
        let keys=PokeRogueOriginalCatalog.shared.manifest.entries.keys.sorted()
        var failures:[String]=[]
        for start in stride(from:0,to:keys.count,by:8) {
            let batch=Array(keys[start..<min(start+8,keys.count)])
            let result=try await player.evaluate("""
            const errors=[];
            for(const move of keys)for(const reverse of [false,true]){
                try{
                    await window.ptbPrepare({move,actors:[{key:'own-0',own:true,slot:0,texture:'audit',sprite:window.auditSprite,x:120,y:298},{key:'foe-0',own:false,slot:0,texture:'audit',sprite:window.auditSprite,x:520,y:168}],source:reverse?'foe-0':'own-0',targets:[{key:reverse?'own-0':'foe-0'}],hit:true,width:800,height:320,scale:2});
                    const completed=window.ptbAdvance(120000);
                    if(!completed.done)throw Error('Original cleanup did not complete');
                }catch(error){errors.push(move+': '+error.stack);}
                window.ptbFinish();
            }
            return {errors};
            """,arguments:["keys":batch])
            failures += result["errors"] as? [String] ?? ["Malformed audit result"]
        }
        XCTAssertEqual(failures,[],failures.joined(separator:"\n"))
        XCTAssertNil(player.error)
    }
    func testUnfocusedProductionWebGLReplaysOriginalMotionBackgroundSpreadAndCleanup() async throws {
        let (store,directory)=try PokeRogueFaithfulTests().gifStore();defer{try? FileManager.default.removeItem(at:directory)}
        let player=PokeRogueBattlePlayer(spriteStore:store)
        let host=NSHostingController(rootView:PokeRogueBattleSurface(player:player).frame(width:800,height:320))
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:800,height:320),styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentViewController=host;window.orderFront(nil)
        defer{player.stop();window.orderOut(nil);window.contentViewController=nil}
        for (move,reverse,spread,hit) in [("quickattack",false,false,true),("thunderbolt",true,false,true),("surf",false,true,true),("psychic",false,false,true),("psychic",false,false,false),("rest",false,false,true)] {
            let task=Task{await player.play(event(move,reverse:reverse,doubles:spread,hit:hit),actors:actors(doubles:spread),size:CGSize(width:800,height:320))}
            try await wait({player.isPlaying || player.error != nil})
            XCTAssertNil(player.error,"\(move)")
            var snapshots:[[String:Any]]=[]
            var samples:[(Date,Double)]=[]
            let end=Date().addingTimeInterval(15)
            while player.isPlaying,Date()<end {
                let snapshot=try await player.inspect();snapshots.append(snapshot)
                samples.append((Date(),snapshot["clock"] as? Double ?? 0))
                try await Task.sleep(for:.milliseconds(65))
            }
            let completed=await task.value
            XCTAssertTrue(completed,"\(move): \(player.error ?? "playback failed")")
            XCTAssertFalse(player.isPlaying)
            let final=try await player.inspect()
            XCTAssertEqual(final["tracks"] as? Int,0);XCTAssertEqual(final["done"] as? Bool,true)
            XCTAssertFalse(snapshots.isEmpty)
            if move=="quickattack" {
                let first=try XCTUnwrap(samples.first),last=try XCTUnwrap(samples.last)
                let rate=(last.1-first.1)/last.0.timeIntervalSince(first.0)/1000
                XCTAssertEqual(rate,1,accuracy:0.15,"Production must preserve the original 1× clock")
                XCTAssertTrue(snapshots.contains{ s in (s["sprites"] as? [[String:Any]] ?? []).contains{($0["texture"] as? String)?.hasPrefix("25") == true && abs(($0["x"] as? Double ?? 0)-120)>5}},"Original USER commands must move the caster")
            }
            if move=="thunderbolt" {
                XCTAssertTrue(snapshots.contains{($0["backdrops"] as? [[String:Any]] ?? []).contains{$0["visible"] as? Bool==true && ($0["alpha"] as? Double ?? 0)>0}},"Original timed background must be visible")
            }
            if spread{XCTAssertTrue(snapshots.contains{$0["tracks"] as? Int==2},"Both actual spread targets need original tracks")}
            if !hit{XCTAssertTrue(snapshots.allSatisfy{($0["graphics"] as? Int ?? 0)==0},"Miss must not animate target impact")}
        }
        let charge=await player.play(event("solarbeam",phase:"charge"),actors:actors(),size:CGSize(width:800,height:320))
        XCTAssertTrue(charge);XCTAssertEqual(PokeRogueOriginalCatalog.shared.key(event("Solar Beam",phase:"charge")),"solarbeam:charge")
        // A resource/JS failure must restore native sprites and retry from a fresh offline player.
        _ = try await player.evaluate("window.ptbPrepare=()=>{throw Error('Missing original asset test')};return {}")
        let failed=await player.play(event("thunderbolt"),actors:actors(),size:CGSize(width:800,height:320))
        XCTAssertFalse(failed);XCTAssertNotNil(player.error);XCTAssertFalse(player.isPlaying)
        let recovered=await player.play(event("quickattack"),actors:actors(),size:CGSize(width:800,height:320))
        XCTAssertTrue(recovered);XCTAssertNil(player.error)
        let pending=Task{_ = try await player.evaluate("await new Promise(resolve=>setTimeout(resolve,500));return {}")}
        try await Task.sleep(for:.milliseconds(30));player.stop()
        do{_ = try await pending.value;XCTFail("Stopped WebKit continuation must be cancelled")}catch{}
        let task=Task{await player.play(event("thunderbolt"),actors:actors(),size:CGSize(width:800,height:320))}
        try await wait({player.isPlaying});task.cancel()
        let canceled=await task.value;XCTAssertFalse(canceled);XCTAssertFalse(player.isPlaying)
        let reduced=await player.play(event("protect"),actors:actors(),size:CGSize(width:800,height:320),reducedMotion:true)
        XCTAssertTrue(reduced);XCTAssertNil(player.error)
    }
}

@MainActor private struct BattleLayerHUDProbe:NSViewRepresentable {
    let view:NSView
    func makeNSView(context:Context)->NSView{view}
    func updateNSView(_ view:NSView,context:Context){}
}
