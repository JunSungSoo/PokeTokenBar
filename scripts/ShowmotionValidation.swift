// Development-only original GPU asset validation; never reads or writes user Pokémon saves.
import AppKit
import SwiftUI
@testable import PokeTokenBar

@MainActor private final class ValidationDelegate: NSObject, NSApplicationDelegate {
    let player=ShowmotionPlayer()
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        let host=NSHostingController(rootView:ZStack {
            Color(red:0.2,green:0.25,blue:0.3)
            ShowmotionSurface(player:player)
        }.frame(width:640,height:360))
        window=NSWindow(contentRect:NSRect(x:200,y:200,width:640,height:360),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.contentViewController=host;window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        window.level = .floating
        Task { @MainActor in
            var results=[[String:Any]]()
            let requested=(CommandLine.arguments.dropFirst().first ?? ProcessInfo.processInfo.environment["PTB_SHOWMOTION_VALIDATE_MOVES"])?.split(separator:",").map(String.init)
                ?? ShowmotionPlayer.moveIDs.sorted()
            for (index,id) in requested.enumerated() {
                guard window.isVisible else { break }
                window.title="Showmotion original · "+id
                let event=BattleVisualEvent(id:index,move:id,type:"Water",category:"Special",
                    source:BattleEffectPosition(own:true,slot:0),targets:[BattleEffectTarget(position:BattleEffectPosition(own:false,slot:0),hit:true)],moveID:id)
                let result=await player.play(event,rects:["own-0":CGRect(x:150,y:195,width:120,height:100),"foe-0":CGRect(x:350,y:85,width:120,height:100)])
                results.append(["move":id,"playedOriginal":result,"detail":player.lastResult,"unavailable":player.unavailable ?? "",
                    "windowVisible":window.isVisible,"appActive":NSApp.isActive])
                print(id,result,player.lastResult,player.unavailable ?? "")
                try? JSONSerialization.data(withJSONObject:results,options:.prettyPrinted)
                    .write(to:URL(fileURLWithPath:"/private/tmp/ptb-showmotion-validation.json"),options:.atomic)
            }
            player.stop();NSApp.terminate(nil)
        }
    }
}
@_cdecl("showmotionvalidationmain") func showmotionvalidationmain() -> Int32 {
    MainActor.assumeIsolated {
        let app=NSApplication.shared,delegate=ValidationDelegate();app.delegate=delegate;app.setActivationPolicy(.regular);app.run()
    };return 0
}
