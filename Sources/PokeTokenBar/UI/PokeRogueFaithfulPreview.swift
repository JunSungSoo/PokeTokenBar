import AppKit
import Observation
import SwiftUI
import WebKit

/// Development comparison only; production battles keep their existing renderer until approved.
@MainActor @Observable
final class PokeRogueFaithfulPlayer {
    static let moves = ["thunderbolt", "protect", "quick-attack", "volt-switch"]
    static var directory: URL {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("PokeRogueFaithful")
        if let bundled, FileManager.default.fileExists(atPath: bundled.appendingPathComponent("index.html").path) { return bundled }
        var root=URL(fileURLWithPath:#filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        return root.appendingPathComponent("Tests/PokeTokenBarTests/Fixtures/PokeRogueFaithful")
    }
    let webView: WKWebView
    private(set) var ready=false
    private(set) var status=L(.ko).faithfulPreviewPreparing
    private(set) var error: String?
    private(set) var frame=0
    private(set) var equal=false
    private var bridge: FaithfulBridge?
    private var process: Process?
    private var input: Pipe?
    private(set) var clockMS=0.0
    private(set) var paused=false
    private(set) var finished=false
    private(set) var updatedAt=Date()
    private var rate=1.0
    private let singlePanel:Bool
    private var began=false
    private let spriteStore: SpriteStore
    init(spriteStore: SpriteStore = .shared,singlePanel:Bool=false) {
        self.spriteStore=spriteStore;self.singlePanel=singlePanel
        let configuration=WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback=[]
        webView=WKWebView(frame:.zero,configuration:configuration)
        webView.setValue(false,forKey:"drawsBackground")
        let bridge=FaithfulBridge(owner:self);self.bridge=bridge
        configuration.userContentController.add(bridge,name:"faithful")
    }
    func start() async {
        guard !began else { return };began=true
        do {
            let process=Process(),output=Pipe(),input=Pipe()
            process.executableURL=BattleEngineProcess.runtimeURL
            process.arguments=[Self.directory.appendingPathComponent("server.cjs").path]
            process.standardOutput=output;process.standardInput=input;process.standardError=FileHandle.nullDevice
            try process.run();self.process=process;self.input=input
            let data=await Task.detached { output.fileHandleForReading.availableData }.value
            struct Address: Decodable { let url:URL }
            let address=try JSONDecoder().decode(Address.self,from:data)
            var components=URLComponents(url:address.url,resolvingAgainstBaseURL:false)!
            if singlePanel { components.queryItems=[URLQueryItem(name:"panels",value:"1")] }
            webView.load(URLRequest(url:components.url!))
        } catch { self.error=error.localizedDescription }
    }
    /// Uses exactly the native GIF decoder, shared crop, stance center and frame delays.
    static func spritePayload(back: Bool, store: SpriteStore = .shared,speciesID:Int=25,shiny:Bool=false,form:PokemonForm?=nil) async throws -> [String:Any] {
        let frames=BattleSpriteGeometry.croppedFrames(await SpriteLoader.recoveringAnimationFrames(speciesID:speciesID,shiny:shiny,store:store,form:form,back:back,onUnavailable:{}))
        guard !frames.isEmpty else { throw BattleFailure.unavailableEngine }
        let center=BattleSpriteGeometry.horizontalCenter(frames)
        let encoded=try frames.map { frame -> String in
            guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:64,pixelsHigh:64,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),
                  let context=NSGraphicsContext(bitmapImageRep:bitmap) else{throw BattleFailure.invalidMessage}
            NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context;context.imageInterpolation = .none
            let size=SpriteFit.size(for:frame.image.size,box:64)
            frame.image.draw(in:NSRect(x:(64-size.width)/2+(0.5-center)*size.width,y:0,width:size.width,height:size.height),from:.zero,operation:.sourceOver,fraction:1)
            NSGraphicsContext.restoreGraphicsState()
            guard let data=bitmap.representation(using:.png,properties:[:]) else { throw BattleFailure.invalidMessage }
            return "data:image/png;base64,"+data.base64EncodedString()
        }
        return ["frames":encoded,"delays":frames.map(\.delay)]
    }
    private func initializeSprites() async {
        do {
            let back=try await Self.spritePayload(back:true,store:spriteStore),front=try await Self.spritePayload(back:false,store:spriteStore)
            _ = try await evaluate("await window.faithfulInitialize(payload);return true",arguments:["payload":["back":back,"front":front]])
        } catch { self.error=error.localizedDescription }
    }
    func configure(move:String,reverse:Bool,rate:Double,sameLayout:Bool,loop:Bool,sound:Bool) {
        guard ready else { return }
        self.rate=rate;self.paused=false;self.clockMS=0;self.updatedAt=Date();self.finished=false
        let payload:[String:Any]=["move":move,"reverse":reverse,"rate":rate,"sameLayout":sameLayout,"loop":loop,"sound":sound]
        webView.callAsyncJavaScript("return window.faithfulConfigure(config)",arguments:["config":payload],in:nil,in:.page) { [weak self] result in
            if case .failure(let error)=result { self?.error=error.localizedDescription }
        }
    }
    func pause(_ paused:Bool) { self.paused=paused;webView.evaluateJavaScript("window.faithfulPause(\(paused))",completionHandler:nil) }
    func seek(_ value:Int) { paused=true;clockMS=Double(value+1)*50;updatedAt=Date();webView.evaluateJavaScript("window.faithfulSeek(\(value))",completionHandler:nil) }
    func evaluate(_ script:String, arguments:[String:Any] = [:]) async throws -> Any {
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            webView.callAsyncJavaScript(script,arguments:arguments,in:nil,in:.page) { result in
                do {
                    let value = try result.get()
                    continuation.resume(returning: try JSONSerialization.data(withJSONObject:value,options:[.fragmentsAllowed]))
                } catch { continuation.resume(throwing:error) }
            }
        }
        return try JSONSerialization.jsonObject(with:data,options:[.fragmentsAllowed])
    }
    func inspect() async throws -> [String:Any] {
        try await evaluate("return window.faithfulInspect()") as? [String:Any] ?? [:]
    }
    fileprivate func receive(_ message:[String:Any]) {
        switch message["kind"] as? String {
        case "boot": status=L(.ko).faithfulPreviewPageReady
        case "loaded": status=L(.ko).faithfulPreviewCodeReady;Task { await initializeSprites() }
        case "ready": ready=true;status=L(.ko).faithfulPreviewReady
        case "status":
            frame=message["frame"] as? Int ?? 0;equal=message["equal"] as? Bool ?? false
            clockMS=message["clock"] as? Double ?? 0;paused=message["paused"] as? Bool ?? false
            finished=(message["done"] as? [Bool])?.allSatisfy({$0}) ?? false;updatedAt=Date()
        case "error": error=message["message"] as? String ?? L(.ko).faithfulPreviewFailed
        default:break
        }
    }
    func stop() {
        webView.evaluateJavaScript("window.faithfulStop?.()",completionHandler:nil)
        webView.stopLoading();try? input?.fileHandleForWriting.close();input=nil
        if process?.isRunning == true { process?.terminate() };process=nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName:"faithful")
    }
}
@MainActor private final class FaithfulBridge:NSObject,WKScriptMessageHandler {
    weak var owner:PokeRogueFaithfulPlayer?
    init(owner:PokeRogueFaithfulPlayer){self.owner=owner}
    func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage){if let body=message.body as? [String:Any]{owner?.receive(body)}}
}
@MainActor struct PokeRogueFaithfulSurface:NSViewRepresentable {
    let player:PokeRogueFaithfulPlayer
    func makeNSView(context:Context)->WKWebView { player.webView }
    func updateNSView(_ view:WKWebView,context:Context){}
}
@MainActor struct PokeRogueFaithfulComparison:View {
    @State private var player=PokeRogueFaithfulPlayer(singlePanel:true)
    @State private var move="thunderbolt"
    @State private var reverse=false
    @State private var rate=1.0
    @State private var loop=true
    @State private var sound=false
    @State private var paused=false
    @State private var selectedFrame=0.0
    private var event:BattleVisualEvent {
        let recipe=BattleEffectCatalog.shared.recipe(for:move)
        return BattleVisualEvent(id:1,move:move,type:recipe?.type ?? "Electric",category:recipe?.category ?? "Special",
            source:.init(own:!reverse,slot:0),targets:[.init(position:.init(own:move=="protect" ? !reverse:reverse,slot:0),hit:true)],moveID:move)
    }
    private var length:Double { PokeRogueBattleCatalog.shared.entry(event)?.length ?? 26 }
    private func replay(){paused=false;player.configure(move:move,reverse:reverse,rate:rate,sameLayout:false,loop:loop,sound:sound)}
    var body:some View {
        VStack(alignment:.leading,spacing:16){
            Text(L(.ko).faithfulPreviewTitle).font(.title2.bold())
            Text(L(.ko).faithfulPreviewSubtitle).font(.caption).foregroundStyle(.secondary)
            HStack {
                Picker(L(.ko).faithfulPreviewMove,selection:$move){ForEach(PokeRogueFaithfulPlayer.moves,id:\.self){Text(BattleTextCatalog.shared.moveName($0,language:.ko)).tag($0)}}.frame(width:250)
                Picker(L(.ko).faithfulPreviewSpeed,selection:$rate){Text(L(.ko).faithfulPreviewOriginalSpeed).tag(1.0);Text("0.65×").tag(0.65);Text("0.5×").tag(0.5)}.frame(width:185)
                Button(L(.ko).faithfulPreviewReplay,action:replay).accessibilityIdentifier("faithful-replay")
                Button(paused ? L(.ko).faithfulPreviewResume:L(.ko).faithfulPreviewPause){paused.toggle();player.pause(paused)}
                Spacer();Toggle(L(.ko).faithfulPreviewLoop,isOn:$loop);Toggle(L(.ko).faithfulPreviewSound,isOn:$sound)
            }.disabled(!player.ready)
            HStack {Text(L(.ko).faithfulPreviewCurrentLabel).frame(maxWidth:.infinity);Text(L(.ko).faithfulPreviewOriginalLabel).frame(maxWidth:.infinity)}.font(.headline)
            HStack(spacing:12) {
                TimelineView(.animation(minimumInterval:1/60)) { timeline in
                    let clock=player.clockMS + (player.paused || player.finished ? 0:timeline.date.timeIntervalSince(player.updatedAt)*1000*rate)
                    let progress=max(0,(clock-50)/(length*50))
                    PokeRogueCurrentPikachuStage(event:event,progress:progress)
                        .frame(width:320,height:180).scaleEffect(532.0/320,anchor:.topLeading)
                        .frame(width:532,height:299.25,alignment:.topLeading).clipped()
                }
                PokeRogueFaithfulSurface(player:player).frame(width:532,height:299.25)
            }.clipShape(RoundedRectangle(cornerRadius:10))
            HStack {
                Toggle(L(.ko).faithfulPreviewReverse,isOn:$reverse);Spacer()
                Text(L(.ko).faithfulPreviewFrame(player.frame)).monospacedDigit()
                Text(L(.ko).faithfulPreviewIdleLabel).font(.caption).foregroundStyle(.secondary)
            }.disabled(!player.ready)
            HStack {Text(L(.ko).faithfulPreviewInspectFrames);Slider(value:$selectedFrame,in:0...max(1,length-1),step:1).onChange(of:selectedFrame){_,v in paused=true;player.seek(Int(v))};Text(L(.ko).faithfulPreviewPausedGIF).font(.caption).foregroundStyle(.secondary)}.disabled(!player.ready)
            Text(L(.ko).faithfulPreviewDetails(player.status)).font(.caption).foregroundStyle(.secondary)
            if let error=player.error {Text(error).foregroundStyle(.red).textSelection(.enabled).accessibilityIdentifier("faithful-error")}
        }.padding(20).frame(width:1120).background(Color(nsColor:.windowBackgroundColor))
        .task{await player.start()}.onChange(of:player.ready){_,v in if v{replay()}}
        .onChange(of:move){_,_ in replay()}.onChange(of:reverse){_,_ in replay()}.onChange(of:rate){_,_ in replay()}
        .onChange(of:loop){_,_ in replay()}.onChange(of:sound){_,_ in replay()}.onDisappear{player.stop()}
    }
}
@MainActor private struct PokeRogueCurrentPikachuStage:View {
    let event:BattleVisualEvent
    let progress:Double
    private let rects=["own-0":CGRect(x:13.5,y:101,width:95,height:80),"foe-0":CGRect(x:215.5,y:20,width:95,height:80)]
    var body:some View {
        ZStack {
            LinearGradient(colors:[Color(red:0.61,green:0.70,blue:0.64),Color(red:0.86,green:0.87,blue:0.71)],startPoint:.top,endPoint:.bottom)
            ForEach([true,false],id:\.self){ own in
                let bounds=rects[own ? "own-0":"foe-0"]!
                BattlePokemonStage(pokemon:.init(id:own ? "own":"foe",speciesID:25,name:"Pikachu",level:37,shiny:false,active:true,form:nil,fainted:false,hp:143,maxHP:143,status:"",stats:nil),back:own,stageSize:75)
                    .position(x:bounds.midX,y:bounds.midY)
            }
            PokeRogueBattleEffects(event:event,rects:rects,progress:progress)
        }.frame(width:320,height:180).clipped()
    }
}
