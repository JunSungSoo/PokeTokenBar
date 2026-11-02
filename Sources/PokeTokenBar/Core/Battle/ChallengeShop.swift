import Foundation

enum ChallengeShopItem:String,Codable,CaseIterable,Identifiable,Sendable {
    case fullRecovery,ppRecovery,heal20,heal40,statusCure,revive,teamHeal30,maxRevive
    var id:String {rawValue}
    var teamWide:Bool {self == .teamHeal30}
    var price:Int {
        switch self {
        case .fullRecovery:100
        case .ppRecovery,.teamHeal30:50
        case .heal20:10
        case .heal40,.revive:30
        case .statusCure:40
        case .maxRevive:70
        }
    }
    func needed(_ state:ChallengePokemonState,maxHP:Int)->Bool {
        if self == .revive || self == .maxRevive{return state.hp==0}
        guard state.hp>0 else{return false}
        switch self {
        case .fullRecovery:return state.hp<maxHP || !state.status.isEmpty || state.moves.contains{$0.pp<$0.maxPP}
        case .ppRecovery:return state.moves.contains{$0.pp<$0.maxPP}
        case .heal20,.heal40,.teamHeal30:return state.hp<maxHP
        case .statusCure:return !state.status.isEmpty
        case .revive,.maxRevive:return false
        }
    }
    func apply(to state:inout ChallengePokemonState,maxHP:Int) {
        guard needed(state,maxHP:maxHP) else{return}
        switch self {
        case .fullRecovery,.maxRevive:state.hp=maxHP
        case .revive:state.hp=max(1,maxHP/2)
        case .ppRecovery,.statusCure:break
        case .heal20,.heal40,.teamHeal30:
            let fraction=self == .heal20 ? 0.2:self == .heal40 ? 0.4:0.3
            state.hp=min(maxHP,state.hp+max(1,Int(Double(maxHP)*fraction)))
        }
        if [.fullRecovery,.statusCure,.revive,.maxRevive].contains(self) {
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
        guard [.reward,.intermission].contains(phase),(shopOffers ?? []).contains(item),pointBalance>=item.price else{return false}
        if item.teamWide {
            return resources.contains{r in item.needed(r,maxHP:team.first{$0.id==r.id}?.stats["hp"] ?? 0)}
        }
        guard let resource=resources.first(where:{$0.id==targetID}),let maxHP=team.first(where:{$0.id==targetID})?.stats["hp"] else{return false}
        return item.needed(resource,maxHP:maxHP)
    }
}
