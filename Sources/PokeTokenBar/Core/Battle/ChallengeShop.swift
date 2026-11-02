import Foundation

enum ChallengeShopItem:String,CaseIterable,Identifiable,Sendable {
    case fullRecovery,ppRecovery,heal20,heal40
    var id:String {rawValue}
    var price:Int {switch self{case .fullRecovery:100;case .ppRecovery:50;case .heal20:10;case .heal40:30}}
    func needed(_ state:ChallengePokemonState,maxHP:Int)->Bool {
        switch self {
        case .fullRecovery:state.hp<maxHP || !state.status.isEmpty || state.moves.contains{$0.pp<$0.maxPP}
        case .ppRecovery:state.moves.contains{$0.pp<$0.maxPP}
        case .heal20,.heal40:state.hp<maxHP
        }
    }
    func apply(to state:inout ChallengePokemonState,maxHP:Int) {
        let fainted=state.hp==0
        switch self {
        case .fullRecovery:state.hp=maxHP
        case .ppRecovery:break
        case .heal20,.heal40:state.hp=min(maxHP,state.hp+max(1,Int(Double(maxHP)*(self == .heal20 ? 0.2:0.4))))
        }
        if self == .fullRecovery || (fainted && self != .ppRecovery) {
            state.status="";state.sleepStart=nil;state.sleepRemaining=nil
        }
        if self == .fullRecovery || self == .ppRecovery {
            for i in state.moves.indices{state.moves[i].pp=state.moves[i].maxPP}
        }
    }
}

extension ChallengeRun {
    var pointBalance:Int {challengePoints ?? 0}
    var completedVictories:Int {
        switch phase {
        case .cleared:encounterCount
        case .reward,.intermission:encounterIndex+1
        case .ready,.battling,.lost:encounterIndex
        }
    }
    func canPurchase(_ item:ChallengeShopItem,targetID:String)->Bool {
        guard [.reward,.intermission].contains(phase),pointBalance>=item.price,
              let resource=resources.first(where:{$0.id==targetID}),let maxHP=team.first(where:{$0.id==targetID})?.stats["hp"] else{return false}
        return item.needed(resource,maxHP:maxHP)
    }
}
