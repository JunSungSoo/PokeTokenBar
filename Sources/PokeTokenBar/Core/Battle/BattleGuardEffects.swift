import Foundation

/// Replay the authored shield on the defending battler only after a real block.
@MainActor enum BattleGuardEffects {
    static func event(scene:BattleScene,log:[String],index:Int,ownPlayer:Int)->BattleVisualEvent? {
        guard log.indices.contains(index) else{return nil}
        let parts=log[index].split(separator:"|",omittingEmptySubsequences:false).map(String.init)
        guard parts.count>3,parts[1]=="-activate",parts[3]=="move: Protect" else{return nil}
        let token=parts[2]
        var move="protect"
        for line in log[..<index].reversed() {
            let prior=line.split(separator:"|",omittingEmptySubsequences:false).map(String.init)
            if prior.count>1,prior[1]=="turn"{break}
            if prior.count>3,prior[1]=="move",prior[2]==token {
                let key=BattleTextCatalog.key(prior[3])
                if ["protect","detect"].contains(key){move=key}
                break
            }
        }
        let source=BattleEffectPosition(own:token.hasPrefix("p\(ownPlayer+1)"),slot:token.hasPrefix("p1b") || token.hasPrefix("p2b") ? 1:0)
        return BattleVisualEvent(id:scene.id,move:move,type:"Normal",category:"Status",source:source,
                                 targets:[BattleEffectTarget(position:source,hit:true)],moveID:move,phase:"guard")
    }
}
