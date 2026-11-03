import Foundation

extension ChallengeRun {
    static func cashReward(encounterIndex:Int)->Int {
        switch encounterIndex {
        case 0..<16:10
        case 16..<24:30
        case 24..<26:50
        default:0
        }
    }
    /// Old saves predate the explicit victory ledger. New runs record actual wins,
    /// so a developer's next-trainer skip never generates money.
    var completedCashRewards:[Int] {
        cashVictoryRewards ?? (0..<completedVictories).map{Self.cashReward(encounterIndex:$0)}
    }
    var defeatCashTokens:Int {
        guard phase == .lost,completedCashRewards.count>=3 else{return 0}
        return completedCashRewards.dropFirst(2).reduce(0,+)*1_000_000
    }
}

extension L {
    func challengeCashAward(_ millions:Int)->String {
        t("챌린지 보상 +\(millions)M", "Challenge reward +\(millions)M", "チャレンジ報酬 +\(millions)M", "Recompensa del desafío +\(millions)M", "Récompense du défi +\(millions)M", "Recompensa do desafio +\(millions)M", "Herausforderungsbelohnung +\(millions)M", "Награда испытания +\(millions)M")
    }
}
