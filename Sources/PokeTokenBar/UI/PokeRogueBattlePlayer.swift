import AppKit
import Observation
import SwiftUI
import WebKit

struct PokeRogueActor:Sendable {
    let pokemon:BattleCombatant
    let position:BattleEffectPosition
    let rect:CGRect
    let pixelScale:CGFloat
    init(pokemon:BattleCombatant,position:BattleEffectPosition,rect:CGRect,pixelScale:CGFloat=1.5) {
        self.pokemon=pokemon;self.position=position;self.rect=rect;self.pixelScale=pixelScale
    }
}
@MainActor final class PokeRogueOriginalCatalog {
    struct Entry:Decodable {let file:String;let frames:[Int];let graphics:[String];let backgrounds:[String];let sounds:[String]}
    struct Manifest:Decodable {let assetRevision:String;let runtimeRevision:String;let entries:[String:Entry];let aliases:[String:String];let fieldEntries:[String:Entry]?}
    static var directory:URL {
        let bundled=Bundle.main.resourceURL?.appendingPathComponent("PokeRoguePlayer")
        if let bundled,FileManager.default.fileExists(atPath:bundled.appendingPathComponent("manifest.json").path){return bundled}
        return Bundle.module.url(forResource:"PokeRoguePlayer",withExtension:nil)!
    }
    static let shared=PokeRogueOriginalCatalog()
    let manifest:Manifest
    private init(){manifest=try! JSONDecoder().decode(Manifest.self,from:Data(contentsOf:Self.directory.appendingPathComponent("manifest.json")))}
    func key(_ event:BattleVisualEvent)->String {
        let raw=BattleTextCatalog.key(event.moveID ?? event.move)
        return (manifest.aliases[raw] ?? raw)+(event.phase=="charge" ? ":charge":"")
    }
    func entry(_ event: BattleVisualEvent) -> Entry? {
        manifest.entries[key(event)] ?? manifest.fieldEntries?[key(event)]
    }
    func estimatedDuration(_ event:BattleVisualEvent)->Double {
        if event.phase == "entry" { return 6 }
        guard let entry=entry(event) else{return 0}
        // Include authored tails and loading margin; the real player completion remains authoritative.
        return Double(entry.frames.max() ?? 0)*0.05+4
    }
}
/// One offline original PokéRogue player per battlefield. Native GIFs remain mounted under it.
@MainActor @Observable final class PokeRogueBattlePlayer {
    let webView:WKWebView
    let backgroundWebView:WKWebView
    private var readyLayers=Set<String>()
    private(set) var ready=false
    private(set) var isPlaying=false
    var entryHiddenPositions=Set<String>()
    private(set) var effectsVolume=0.0
    private(set) var error:String?
    private var bridge:RogueBattleBridge?
    private var process:Process?
    private var input:Pipe?
    private var starting=false
    private var generation=UUID()
    private var payloads:[String:[String:Any]]=[:]
    private var order:[String]=[]
    private var evaluations:[UUID:CheckedContinuation<Data,Error>]=[:]
    private let spriteStore:SpriteStore
    init(spriteStore:SpriteStore = .shared){
        self.spriteStore=spriteStore
        let configuration=WKWebViewConfiguration();configuration.mediaTypesRequiringUserActionForPlayback=[]
        webView=WKWebView(frame:.zero,configuration:configuration);webView.setValue(false,forKey:"drawsBackground")
        backgroundWebView=WKWebView(frame:.zero,configuration:configuration);backgroundWebView.setValue(false,forKey:"drawsBackground")
        let bridge=RogueBattleBridge(owner:self);self.bridge=bridge;configuration.userContentController.add(bridge,name:"rogue")
    }
    func setEffectsVolume(_ value: Double) {
        effectsVolume = value.isFinite ? min(1, max(0, value)) : 0.35
        if ready { webView.evaluateJavaScript("window.ptbSetEffectsVolume?.(\(effectsVolume))", completionHandler: nil) }
    }
    func start() async {
        guard process==nil,!starting else{return};starting=true;defer{starting=false}
        ready=false;readyLayers=[];error=nil
        do{
            let child=Process(),output=Pipe(),input=Pipe();child.executableURL=BattleEngineProcess.runtimeURL
            child.arguments=[PokeRogueOriginalCatalog.directory.appendingPathComponent("server.cjs").path]
            child.standardOutput=output;child.standardInput=input;child.standardError=FileHandle.nullDevice
            try child.run();process=child;self.input=input
            let bytes=await Task.detached{output.fileHandleForReading.availableData}.value
            struct Address:Decodable{let url:URL}
            let url=try JSONDecoder().decode(Address.self,from:bytes).url
            webView.load(URLRequest(url:url))
            var background=URLComponents(url:url,resolvingAgainstBaseURL:false)!
            background.queryItems=[URLQueryItem(name:"layer",value:"background")]
            backgroundWebView.load(URLRequest(url:background.url!))
        }catch{self.error="\(error.localizedDescription): \((error as NSError).userInfo)"}
    }
    func evaluate(_ script:String,arguments:[String:Any]=[:],background:Bool=false) async throws -> [String:Any] {
        let id=UUID()
        let bytes:Data=try await withCheckedThrowingContinuation{ continuation in
            evaluations[id]=continuation
            (background ? backgroundWebView:webView).callAsyncJavaScript(script,arguments:arguments,in:nil,in:.page){[weak self] result in
                guard let c=self?.evaluations.removeValue(forKey:id) else{return}
                do{c.resume(returning:try JSONSerialization.data(withJSONObject:result.get(),options:[.fragmentsAllowed]))}
                catch{c.resume(throwing:error)}
            }
            Task{@MainActor [weak self] in
                try? await Task.sleep(for:.seconds(15))
                if let c=self?.evaluations.removeValue(forKey:id){c.resume(throwing:BattleFailure.unavailableEngine)}
            }
        }
        return (try JSONSerialization.jsonObject(with:bytes,options:[.fragmentsAllowed]) as? [String:Any]) ?? [:]
    }
    private func evaluateLayers(_ script:String,arguments:[String:Any]=[:]) async throws -> [String:Any] {
        _ = try await evaluate(script,arguments:arguments,background:true)
        return try await evaluate(script,arguments:arguments)
    }
    private func sprite(_ pokemon:BattleCombatant,back:Bool,reduced:Bool) async throws -> (String,[String:Any]) {
        let key=SpriteStore.cacheKey(speciesID:pokemon.speciesID,animated:!reduced,shiny:pokemon.shiny,form:pokemon.form,back:back)
        if let cached=payloads[key]{return(key,cached)}
        var frames:[(image:NSImage,delay:TimeInterval)]=[]
        if !reduced {
            frames=BattleSpriteGeometry.croppedFrames(await SpriteLoader.recoveringAnimationFrames(speciesID:pokemon.speciesID,shiny:pokemon.shiny,store:spriteStore,form:pokemon.form,back:back,onUnavailable:{}))
        }
        if frames.isEmpty,let data=await spriteStore.data(speciesID:pokemon.speciesID,animated:false,shiny:pokemon.shiny,form:pokemon.form,back:back),let image=NSImage(data:data){frames=[(BattleSpriteGeometry.cropped(image),1)]}
        guard !frames.isEmpty else{throw BattleFailure.unavailableEngine}
        let center=BattleSpriteGeometry.horizontalCenter(frames)
        let encoded=try frames.map{ frame -> String in
            let target=PokeRogueSpriteSizes.shared.size(speciesID:pokemon.speciesID,form:pokemon.form,back:back)
            let fit=SpriteFit.size(for:frame.image.size,width:target.width,height:target.height)
            // Reserve both sides of the stance so tails/wings are not clipped by the atlas.
            let width=ceil(max(target.width,2*max(center,1-center)*fit.width))
            guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(width),pixelsHigh:Int(ceil(target.height)),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),
                  let context=NSGraphicsContext(bitmapImageRep:bitmap) else{throw BattleFailure.invalidMessage}
            // Explicit 1px backing: lockFocus() silently doubles atlases on Retina displays.
            NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context;context.imageInterpolation = .none
            frame.image.draw(in:NSRect(x:width/2-center*fit.width,y:0,width:fit.width,height:fit.height),from:.zero,operation:.sourceOver,fraction:1)
            NSGraphicsContext.restoreGraphicsState()
            guard let bytes=bitmap.representation(using:.png,properties:[:]) else{throw BattleFailure.invalidMessage}
            return "data:image/png;base64,"+bytes.base64EncodedString()
        }
        let value:[String:Any]=["frames":encoded,"delays":frames.map(\.delay)]
        payloads[key]=value;order.append(key)
        while order.count>12{payloads.removeValue(forKey:order.removeFirst())}
        return(key,value)
    }
    func play(_ event:BattleVisualEvent,actors:[PokeRogueActor],size:CGSize,reducedMotion:Bool=false,previousActor:PokeRogueActor?=nil,entrySources:[BattleEffectPosition]=[],previousActors:[PokeRogueActor]=[],beforeFinish:()->Void = {}) async -> Bool {
        if error != nil{stop()}
        let run=generation
        do{
            await start();let until=Date().addingTimeInterval(15)
            while !ready,error==nil,Date()<until,!Task.isCancelled{try await Task.sleep(for:.milliseconds(25))}
            guard ready,error==nil,!Task.isCancelled,run==generation else{return false}
            let source=actors.first{$0.position==event.source}
            guard let source else{throw BattleFailure.invalidMessage}
            let scale=source.pixelScale
            var members:[[String:Any]]=[]
            for actor in actors {
                let (texture,data)=try await sprite(actor.pokemon,back:actor.position.own,reduced:reducedMotion)
                members.append(["key":actor.position.key,"own":actor.position.own,"slot":actor.position.slot,"shiny":actor.pokemon.shiny,"texture":texture,"sprite":data,
                    "x":actor.rect.midX,"y":actor.rect.maxY-BattleSpriteGeometry.footInset,"visible":!entryHiddenPositions.contains(actor.position.key)])
            }
            guard !Task.isCancelled,run==generation else{return false}
            let hitTargets=event.targets.filter(\.hit),targets=hitTargets.isEmpty ? event.targets:hitTargets
            var payload:[String:Any]=["move":PokeRogueOriginalCatalog.shared.key(event),"actors":members,"source":event.source.key,
                "targets":targets.map{["key":$0.position.key]},"hit":!hitTargets.isEmpty,"width":max(1,size.width),"height":max(1,size.height),"scale":scale,"effectsVolume":effectsVolume,"globalField":BattleFieldEffects.isGlobal(event)]
            if event.phase == "entry" {
                payload["transition"]=true
                payload["entrySources"]=(entrySources.isEmpty ? [event.source]:entrySources).map(\.key)
                var outgoing:[[String:Any]]=[]
                for old in previousActors + (previousActor.map{[$0]} ?? []) {
                    guard let incoming=actors.first(where:{$0.position==old.position}),old.pokemon.id != incoming.pokemon.id,!old.pokemon.fainted else{continue}
                    let (texture,data)=try await sprite(old.pokemon,back:old.position.own,reduced:reducedMotion)
                    outgoing.append(["key":"entry-outgoing-"+old.position.key,"own":old.position.own,"slot":old.position.slot,"shiny":old.pokemon.shiny,"texture":texture,"sprite":data,
                        "x":old.rect.midX,"y":old.rect.maxY-BattleSpriteGeometry.footInset])
                }
                payload["previousActors"]=outgoing
            }
            _ = try await evaluateLayers("return await window.ptbPrepare(payload)",arguments:["payload":payload])
            guard !Task.isCancelled,run==generation else{return false}
            _ = try await evaluate("return {volume: window.ptbSetEffectsVolume(volume)}", arguments: ["volume": effectsVolume])
            isPlaying=true
            if reducedMotion {
                let entry=PokeRogueOriginalCatalog.shared.entry(event)
                _ = try await evaluateLayers("return window.ptbAdvance(delta)",arguments:["delta":(event.phase == "entry" ? 10000 : Double(entry?.frames.max() ?? 1)*25)])
                try await Task.sleep(for:.seconds(1.4))
            }else{
                var previous=Date();let deadline=previous.addingTimeInterval(60)
                while !Task.isCancelled,run==generation {
                    let now=Date(),delta=max(1,now.timeIntervalSince(previous)*1000);previous=now
                    let reply=try await evaluateLayers("return window.ptbAdvance(delta)",arguments:["delta":delta])
                    if reply["done"] as? Bool==true{break}
                    guard Date()<deadline else{throw BattleFailure.unavailableEngine}
                    try await Task.sleep(for:.milliseconds(33))
                }
            }
            guard !Task.isCancelled,run==generation else {
                if run==generation { stop() };return false
            }
            beforeFinish()
            _ = try await evaluateLayers("return window.ptbFinish()")
            isPlaying=false;return !Task.isCancelled && run==generation
        }catch{
            guard run==generation else{return false}
            if !Task.isCancelled{self.error="\(error.localizedDescription): \((error as NSError).userInfo)"}
            for view in [backgroundWebView,webView]{view.evaluateJavaScript("window.ptbFinish?.()",completionHandler:nil)};isPlaying=false;return false
        }
    }
    func inspect() async throws -> [String:Any]{try await evaluate("return window.ptbInspect()")}
    fileprivate func receive(_ data:[String:Any]){
        if data["kind"] as? String=="ready"{readyLayers.insert(data["layer"] as? String ?? "foreground");ready=readyLayers.count==2}
        if data["kind"] as? String=="error"{error=data["message"] as? String ?? "PokéRogue unavailable"}
    }
    func stop(){
        generation=UUID();isPlaying=false;entryHiddenPositions=[];ready=false;readyLayers=[];error=nil
        for view in [backgroundWebView,webView]{view.evaluateJavaScript("window.ptbFinish?.()",completionHandler:nil);view.stopLoading()}
        let pending=evaluations.values;evaluations=[:];for c in pending{c.resume(throwing:CancellationError())}
        try? input?.fileHandleForWriting.close();input=nil
        if process?.isRunning==true{process?.terminate()};process=nil
        payloads=[:];order=[]
    }
}
@MainActor private final class RogueBattleBridge:NSObject,WKScriptMessageHandler{
    weak var owner:PokeRogueBattlePlayer?
    init(owner:PokeRogueBattlePlayer){self.owner=owner}
    func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage){if let data=message.body as? [String:Any]{owner?.receive(data)}}
}
@MainActor struct PokeRogueBattleSurface:NSViewRepresentable{
    let player:PokeRogueBattlePlayer
    var background=false
    func makeNSView(context:Context)->WKWebView{background ? player.backgroundWebView:player.webView}
    func updateNSView(_ view:WKWebView,context:Context){}
}
@MainActor struct PokeRogueArena:View{
    var body:some View{
        if let image=NSImage(contentsOf:PokeRogueOriginalCatalog.directory.appendingPathComponent("images/arenas/plains_bg.png")){
            Image(nsImage:image).resizable().interpolation(.none).scaledToFill()
        }
    }
}

/// Backgrounds below native HUD/sprites, original actors and particles above the HUD.
@MainActor struct PokeRogueBattlefieldLayers:ViewModifier {
    let player:PokeRogueBattlePlayer
    func body(content:Content)->some View {
        content
            .background{PokeRogueBattleSurface(player:player,background:true).allowsHitTesting(false).accessibilityHidden(true).task{await player.start()}}
            .background{GeometryReader{g in PokeRogueArena().frame(width:g.size.width,height:g.size.height).clipped()}}
            .overlay{PokeRogueBattleSurface(player:player).allowsHitTesting(false).accessibilityHidden(true)}
    }
}
