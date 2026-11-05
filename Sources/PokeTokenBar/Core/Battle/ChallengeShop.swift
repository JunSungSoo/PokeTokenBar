import Foundation

enum ChallengeShopItem:String,Codable,CaseIterable,Identifiable,Sendable {
    case fullRecovery,ppRecovery,heal20,heal40,statusCure,revive,maxRevive,ppMoveRecovery
    // Keep the released save key while upgrading the effect to 50%.
    case teamHeal50 = "teamHeal30"
    // Retired cases decode existing saves only; never offer or apply them.
    static let allCases:[Self]=[.fullRecovery,.ppRecovery,.heal20,.heal40,.statusCure,.teamHeal50,.ppMoveRecovery]
    var available:Bool {Self.allCases.contains(self)}
    var id:String {rawValue}
    var teamWide:Bool {self == .teamHeal50 || self == .fullRecovery}
    var price:Int {
        switch self {
        case .fullRecovery:100
        case .ppRecovery:30
        case .teamHeal50:50
        case .heal20,.ppMoveRecovery,.statusCure:10
        case .heal40:20
        case .revive:30
        case .maxRevive:70
        }
    }
    func needed(_ state:ChallengePokemonState,maxHP:Int,moveIndex:Int?=nil)->Bool {
        switch self {
        case .fullRecovery:return state.hp<maxHP || !state.status.isEmpty || state.moves.contains{$0.pp<$0.maxPP}
        case .ppRecovery:return state.moves.contains{$0.pp<$0.maxPP}
        case .ppMoveRecovery:
            guard let moveIndex else{return state.moves.contains{$0.pp<$0.maxPP}}
            return state.moves.indices.contains(moveIndex) && state.moves[moveIndex].pp<state.moves[moveIndex].maxPP
        case .heal20,.heal40,.teamHeal50:return state.hp<maxHP
        case .statusCure:return state.hp>0 && !state.status.isEmpty
        case .revive,.maxRevive:return false
        }
    }
    func apply(to state:inout ChallengePokemonState,maxHP:Int,moveIndex:Int?=nil) {
        guard needed(state,maxHP:maxHP,moveIndex:moveIndex) else{return}
        let wasFainted=state.hp==0
        switch self {
        case .fullRecovery:state.hp=maxHP
        case .revive,.maxRevive:return
        case .ppMoveRecovery:
            guard let moveIndex else{return}
            state.moves[moveIndex].pp=state.moves[moveIndex].maxPP
        case .ppRecovery,.statusCure:break
        case .heal20,.heal40,.teamHeal50:
            let fraction=self == .heal20 ? 0.2:self == .heal40 ? 0.4:0.5
            state.hp=min(maxHP,state.hp+max(1,Int(Double(maxHP)*fraction)))
        }
        if self == .fullRecovery || self == .statusCure || (wasFainted && state.hp>0) {
            state.status="";state.sleepStart=nil;state.sleepRemaining=nil
        }
        if self == .fullRecovery || self == .ppRecovery {
            for i in state.moves.indices{state.moves[i].pp=state.moves[i].maxPP}
        }
    }
}

extension ChallengeRun {
    static let startingPoints = 100
    static let rewardPoints = 50
    static func legacyVictoryPoints(_ count: Int) -> Int {
        (0..<count).reduce(0) { total, encounter in total + 100 + 20 * (encounter / 3) }
    }
    func shopPrice(_ item:ChallengeShopItem)->Int {item.price+5*(shopPurchaseCounts?[item.rawValue] ?? 0)}
    var pointBalance:Int {challengePoints ?? 0}
    var completedVictories:Int {
        switch phase {
        case .cleared:encounterCount
        case .reward,.intermission:encounterIndex+1
        case .ready,.battling,.lost:encounterIndex
        }
    }
    func canPurchase(_ item:ChallengeShopItem,targetID:String,moveIndex:Int?=nil)->Bool {
        guard item.available,[.reward,.intermission].contains(phase),(shopOffers ?? []).contains(item),pointBalance>=shopPrice(item) else{return false}
        if item.teamWide {
            return resources.contains{r in item.needed(r,maxHP:team.first{$0.id==r.id}?.stats["hp"] ?? 0)}
        }
        guard let resource=resources.first(where:{$0.id==targetID}),let maxHP=team.first(where:{$0.id==targetID})?.stats["hp"] else{return false}
        return item.needed(resource,maxHP:maxHP,moveIndex:moveIndex)
    }
}
