import Foundation

/// Only direct damage belonging to one explicitly spread move may drain together.
/// Recovery, recoil, residual damage and repeated strikes are ordered engine events.
enum BattleHealthEffects {
    struct Context {
        let group: Int?
        let repeatedHit: Bool
    }
    static func context(log: [String], index: Int, offset: Int) -> Context {
        let none=Context(group:nil,repeatedHit:false)
        guard log.indices.contains(index) else { return none }
        let parts=log[index].split(separator:"|",omittingEmptySubsequences:false)
        guard parts.count > 3, parts[1] == "-damage", !parts.dropFirst(4).contains(where:{$0.hasPrefix("[from] ")}) else { return none }
        var repeated=false
        for previous in log.indices.prefix(index).reversed() {
            let prior=log[previous].split(separator:"|",omittingEmptySubsequences:false)
            guard prior.count > 1 else { continue }
            if prior[1] == "turn" || prior[1].isEmpty { break }
            if prior[1] == "-damage",prior.count > 3,prior[2]==parts[2],!prior.dropFirst(4).contains(where:{$0.hasPrefix("[from] ")}) { repeated=true }
            if prior[1] == "move" {
                let spread=prior.first(where:{$0.hasPrefix("[spread] ")})
                return Context(group:spread == nil ? nil:offset+previous,repeatedHit:repeated)
            }
        }
        return none
    }
    static func canBatch(_ first: BattleVisualEvent, _ next: BattleVisualEvent) -> Bool {
        first.phase == "health" && next.phase == "health" && first.healthGroup != nil && first.healthGroup == next.healthGroup
    }
}
