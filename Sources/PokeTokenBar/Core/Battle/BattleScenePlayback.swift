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

    func reset() { frame = nil; latest = nil; pending = false; acceptedID = -1 }
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
    func finish() { frame = latest; pending = false }
}
