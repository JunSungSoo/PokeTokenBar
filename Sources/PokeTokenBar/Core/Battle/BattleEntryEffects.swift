import Foundation

/// Public switch/drag slots only. Illusion's `replace` does not throw another ball.
enum BattleEntryEffects {
    static func canAppearTogether(_ first:BattleVisualEvent,_ next:BattleVisualEvent)->Bool {
        first.phase=="entry" && next.phase=="entry" && first.source.own==next.source.own && first.source.slot != next.source.slot
    }
    static func event(scene: BattleScene, line: String, ownPlayer: Int) -> BattleVisualEvent? {
        let parts=line.split(separator:"|",omittingEmptySubsequences:false).map(String.init)
        guard parts.count>2,["switch","drag"].contains(parts[1]) else{return nil}
        let token=parts[2].split(separator:":").first.map(String.init) ?? ""
        guard token.count==3,let side=token.dropFirst().first,let slot=token.last,
              token.first=="p",["1","2"].contains(side),["a","b"].contains(slot) else{return nil}
        let source=BattleEffectPosition(own:Int(String(side))==ownPlayer+1,slot:slot=="a" ? 0:1)
        return BattleVisualEvent(id:scene.id,move:"",type:"",category:"Status",source:source,targets:[],phase:"entry")
    }
}
