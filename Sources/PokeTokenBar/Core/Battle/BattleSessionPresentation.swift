import Foundation

/// Shared native battle rendering; networking remains the peer coordinator's responsibility.
@MainActor protocol BattleSessionPresentation: AnyObject {
    var identity:BattleIdentity {get}
    var opponent:BattleIdentity? {get}
    var presentation:BattleScenePlayback {get}
    var frame:BattleFrame? {get}
    var phase:BattleCoordinator.Phase {get}
    var mode:BattleMode {get}
    var arena:BattleArena {get}
    var registeredTeam:[BattlePokemon] {get}
    var opponentRoster:[BattleRosterMember] {get}
    var decisionDeadline:Date? {get}
    var submitted:Bool {get}
    var outcome:String? {get}
    var error:String? {get}
    var isHost:Bool {get}
    var isChallenge:Bool {get}
    func choose(_ decision:BattleDecision)
    func completePresentation()
    func connectManual(_ code:String)
}
extension BattleSessionPresentation {var isChallenge:Bool {false}}
extension BattleCoordinator:BattleSessionPresentation {}
