import AppKit
import Observation
import SwiftUI
import WebKit

@MainActor
@Observable
final class ShowmotionPlayer {
    static let moveIDs: Set<String> = ["swordsdance","moonblast","mysticalfire","shadowball","willowisp","psychic","hydropump","gunkshot","flowertrick"]
    static func supports(_ event: BattleVisualEvent) -> Bool {
        event.phase != "charge" && moveIDs.contains(BattleTextCatalog.key(event.moveID ?? event.move)) && event.targets.contains { $0.hit }
    }
    static var directory: URL {
        let bundled=Bundle.main.resourceURL?.appendingPathComponent("Showmotion")
        return bundled.flatMap { FileManager.default.fileExists(atPath:$0.appendingPathComponent("index.html").path) ? $0 : nil }
            ?? Bundle.module.url(forResource:"Showmotion",withExtension:nil)!
    }
    private(set) var ready=false
    private(set) var isPlaying=false
    private(set) var lastResult=""
    private(set) var unavailable: String?
    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored private var bridge: ShowmotionBridge?
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var input: Pipe?
    @ObservationIgnored private var continuation: CheckedContinuation<Bool,Never>?
    @ObservationIgnored private var currentID: Int?
    @ObservationIgnored private var starting=false
    init() {
        let configuration=WKWebViewConfiguration()
        webView=WKWebView(frame:.zero,configuration:configuration)
        webView.setValue(false,forKey:"drawsBackground")
        let bridge=ShowmotionBridge(owner:self);self.bridge=bridge
        configuration.userContentController.add(bridge,name:"showmotion")
    }
    private func start() async {
        guard process == nil && !starting else { return }
        ready=false;unavailable=nil
        starting=true;defer { starting=false }
        do {
            let child=Process(), output=Pipe(), input=Pipe()
            child.executableURL=BattleEngineProcess.runtimeURL
            child.arguments=[Self.directory.appendingPathComponent("server.cjs").path]
            child.standardOutput=output;child.standardInput=input;child.standardError=FileHandle.nullDevice
            try child.run();process=child;self.input=input
            Task { @MainActor [weak self] in
                try? await Task.sleep(for:.seconds(10))
                if let self, !self.ready && self.unavailable == nil { self.unavailable="Showmotion initialization timed out";self.process?.terminate() }
            }
            let data=await Task.detached { output.fileHandleForReading.availableData }.value
            struct Address: Decodable { let url: URL }
            let address=try JSONDecoder().decode(Address.self,from:data)
            webView.load(URLRequest(url:address.url))
        } catch { unavailable=String(describing:error);AppLog.write("Showmotion startup: \(error)") }
    }
    func play(_ event: BattleVisualEvent,rects: [String:CGRect]) async -> Bool {
        guard Self.supports(event), !Task.isCancelled else { return false }
        await start()
        let deadline=Date().addingTimeInterval(11)
        while !ready && unavailable == nil && Date()<deadline && !Task.isCancelled {
            try? await Task.sleep(for:.milliseconds(25))
        }
        guard ready, unavailable == nil, !Task.isCancelled, let source=rects[event.source.key] else { return false }
        let target=event.targets.first(where: { $0.hit }).flatMap { rects[$0.position.key] }
        let own=event.source.own ? source : (target ?? rects["own-0"] ?? source)
        let foe=event.source.own ? (target ?? rects["foe-0"] ?? source) : source
        // Self effects still use the opposite stage as the original camera's second anchor.
        let selfMove=BattleTextCatalog.key(event.moveID ?? event.move)=="swordsdance"
        let ownPoint = selfMove && !event.source.own ? (rects["own-0"] ?? own) : own
        let foePoint = selfMove && event.source.own ? (rects["foe-0"] ?? foe) : foe
        let payload: [String:Any] = ["id":event.id,"moveID":BattleTextCatalog.key(event.moveID ?? event.move),"ownSource":event.source.own,
            "own":["x":ownPoint.midX,"y":ownPoint.midY],"foe":["x":foePoint.midX,"y":foePoint.midY]]
        currentID=event.id
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation=continuation
                webView.callAsyncJavaScript("await window.ptbPlay(payload); return true",arguments:["payload":payload],in:nil,in:.page) { [weak self] result in
                    if case .failure(let error)=result { self?.finish(false,detail:String(describing:error)) }
                }
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for:.seconds(16))
                    if let self, self.currentID == event.id {
                        self.unavailable="Original effect playback timed out"
                        self.webView.evaluateJavaScript("window.ptbStop?.()",completionHandler:nil)
                        self.finish(false,detail:"Original effect playback timed out")
                    }
                }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.stopPlayback() } }
    }
    fileprivate func message(_ data: [String:Any]) {
        switch data["kind"] as? String {
        case "ready": ready=true
        case "started": isPlaying=true
        case "finished":
            guard (data["id"] as? Int)==currentID else { return }
            finish(data["played"] as? Bool == true,detail:"particles=\(data["particles"] ?? 0), draws=\(data["draws"] ?? 0)")
        case "failed":
            guard (data["id"] as? Int)==currentID else { return }
            finish(false,detail:data["message"] as? String ?? "Effect failure")
        case "unavailable": unavailable=data["message"] as? String ?? "WebGPU unavailable"
        case "error": AppLog.write("Showmotion JavaScript: \(data["message"] ?? "error")")
        default: break
        }
    }
    private func finish(_ played: Bool,detail: String) {
        lastResult="\(played ? "Showmotion original" : "Showmotion fallback"): \(detail)"
        AppLog.write(lastResult)
        isPlaying=false;currentID=nil
        let pending=continuation;continuation=nil;pending?.resume(returning:played)
    }
    func stopPlayback() {
        webView.evaluateJavaScript("window.ptbStop?.()",completionHandler:nil)
        if continuation != nil { finish(false,detail:"Stopped") } else { isPlaying=false }
    }
    func stop() {
        stopPlayback();webView.stopLoading();webView.loadHTMLString("",baseURL:nil)
        try? input?.fileHandleForWriting.close();input=nil
        if process?.isRunning == true { process?.terminate() };process=nil
    }
}

@MainActor
private final class ShowmotionBridge: NSObject, WKScriptMessageHandler {
    weak var owner: ShowmotionPlayer?
    init(owner: ShowmotionPlayer) { self.owner=owner }
    func userContentController(_ userContentController: WKUserContentController,didReceive message: WKScriptMessage) {
        if let data=message.body as? [String:Any] { owner?.message(data) }
    }
}

@MainActor
struct ShowmotionSurface: NSViewRepresentable {
    let player: ShowmotionPlayer
    func makeNSView(context: Context) -> WKWebView { player.webView }
    func updateNSView(_ view: WKWebView,context: Context) {}
}
