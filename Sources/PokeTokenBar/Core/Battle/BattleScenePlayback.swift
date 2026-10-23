import Foundation
import Observation

/// Both the battlefield and auxiliary panels observe the same presented moment.
/// Authoritative requests stay separate and cannot visually jump ahead of effects.
@MainActor @Observable
final class BattleScenePlayback {
    private(set) var frame: BattleFrame?
    private(set) var pending = false
    private var latest: BattleFrame?
    private var acceptedID = -1
    private var generation = 0

    func reset() { generation += 1; frame = nil; latest = nil; pending = false; acceptedID = -1 }
    func accept(_ next: BattleFrame) {
        latest = next
        let last = next.scenes?.last?.id ?? -1
        if frame == nil { frame = next }
        else if last > acceptedID { pending = true }
        else if !pending { frame = next }
        acceptedID = max(acceptedID, last)
    }
    func apply(_ scene: BattleScene) {
        guard let previous = frame else { return }
        frame = BattleFrame(revision: previous.revision, turn: scene.turn,
            decisionID: previous.decisionID, preview: previous.preview, waiting: previous.waiting,
            own: scene.own, foe: scene.foe, slots: previous.slots, log: previous.log,
            effects: previous.effects, field: scene.field, logOffset: previous.logOffset,
            scenes: previous.scenes, ended: false, winner: nil)
    }
    /// Animate only the currently visible individual; switching/max-HP changes snap.
    func animate(_ scene: BattleScene) async {
        guard let previous = frame else { return }
        let token = generation
        func duration(_ old: [BattleCombatant], _ next: [BattleCombatant]) -> Double {
            old.filter(\.active).compactMap { p -> Double? in
                guard let target = next.first(where: { $0.id == p.id && $0.active && $0.maxHP == p.maxHP }), target.hp != p.hp else { return nil }
                return 0.4 + 0.4 * min(1, Double(abs(target.hp-p.hp))/Double(max(1,p.maxHP)))
            }.max() ?? 0
        }
        let seconds = max(duration(previous.own,scene.own),duration(previous.foe,scene.foe))
        guard seconds > 0 else { apply(scene); return }
        let steps = Int(ceil(seconds*30))
        func interpolate(_ old: [BattleCombatant], _ next: [BattleCombatant], _ progress: Double) -> [BattleCombatant] {
            old.map { p in
                guard p.active, let target = next.first(where: { $0.id == p.id && $0.active && $0.maxHP == p.maxHP }) else { return p }
                return BattleCombatant(id:p.id,speciesID:p.speciesID,name:p.name,level:p.level,shiny:p.shiny,active:p.active,form:p.form,
                    fainted:p.fainted,hp:Int((Double(p.hp)+Double(target.hp-p.hp)*progress).rounded()),maxHP:p.maxHP,status:p.status,
                    stats:p.stats,boosts:p.boosts,ability:p.ability)
            }
        }
        for step in 1...steps {
            do { try await Task.sleep(for:.seconds(seconds/Double(steps))) } catch { return }
            guard token == generation, !Task.isCancelled else { return }
            if step == steps { apply(scene) }
            else {
                let progress=Double(step)/Double(steps)
                apply(BattleScene(id:scene.id,turn:scene.turn,own:interpolate(previous.own,scene.own,progress),
                    foe:interpolate(previous.foe,scene.foe,progress),field:previous.field ?? scene.field))
            }
        }
    }
    func finish() { generation += 1; frame = latest; pending = false }
}
