import Foundation

/// Replay activation events, never infer repeated procs from a battler's persistent status.
/// CommonBattleAnim uses the affected Pokémon as both user and target in PokéRogue.
enum BattleStatusEffects {
    static let animations = ["slp": "commonsleep", "psn": "commonpoison", "tox": "commontoxic",
        "par": "commonparalysis", "confusion": "commonconfusion", "brn": "commonburn",
        "frz": "commonfrozen", "attract": "commonattract"]

    static func event(scene: BattleScene, line: String, ownPlayer: Int) -> BattleVisualEvent? {
        let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 3 else { return nil }
        let token = parts[2].split(separator: ":").first.map(String.init) ?? ""
        guard token.count == 3, token.first == "p", let side = token.dropFirst().first,
              ["1", "2"].contains(side), let slot = token.last, ["a", "b"].contains(slot) else { return nil }
        let source = BattleEffectPosition(own: Int(String(side)) == ownPlayer + 1, slot: slot == "a" ? 0 : 1)
        let key: String
        switch parts[1] {
        case "cant":
            // Attract already emits -activate before cant; do not play it twice.
            guard ["slp", "par", "frz"].contains(parts[3]) else { return nil }
            key = parts[3]
        case "-status": key = parts[3]
        case "-start", "-activate":
            let condition = BattleTextCatalog.key(parts[3].components(separatedBy: ": ").last ?? "")
            guard ["confusion", "attract"].contains(condition) else { return nil }
            key = condition
        case "-damage":
            guard let cause = parts.dropFirst(4).first(where: { $0.hasPrefix("[from] ") }),
                  ["[from] psn", "[from] brn"].contains(cause) else { return nil }
            let members = source.own ? scene.own.filter(\.active) : scene.foe
            // Showdown reports both poison and toxic residual damage as [from] psn.
            key = cause == "[from] brn" ? "brn" : (members.indices.contains(source.slot) && members[source.slot].status == "tox" ? "tox" : "psn")
        default: return nil
        }
        guard let animation = animations[key] else { return nil }
        return BattleVisualEvent(id: scene.id, move: animation, type: "", category: "Status", source: source,
            targets: [BattleEffectTarget(position: source, hit: true)], moveID: animation, phase: "status")
    }
}
