import Foundation

/// Animate only an authoritative weather HP loss; immunity/suppression needs no inference.
enum BattleWeatherHitEffects {
    static func event(scene:BattleScene,line:String,ownPlayer:Int)->BattleVisualEvent? {
        let parts=line.split(separator:"|",omittingEmptySubsequences:false).map(String.init)
        guard parts.count>4,parts[1]=="-damage",
              let cause=parts.dropFirst(4).first(where:{$0.hasPrefix("[from] ")}) else{return nil}
        let weather=BattleTextCatalog.key(String(cause.dropFirst(7)))
        guard ["sandstorm","hail"].contains(weather) else{return nil}
        let token=parts[2].split(separator:":").first.map(String.init) ?? ""
        guard token.count==3,token.first=="p",let side=token.dropFirst().first,["1","2"].contains(side),
              let slot=token.last,["a","b"].contains(slot) else{return nil}
        let source=BattleEffectPosition(own:Int(String(side))==ownPlayer+1,slot:slot=="b" ? 1:0)
        return BattleVisualEvent(id:scene.id,move:weather,type:weather=="hail" ? "ice":"rock",category:"Status",
            source:source,targets:[.init(position:source,hit:true)],moveID:weather,phase:"weather-hit")
    }
}
