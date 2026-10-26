import Foundation

/// Presentation only. BW2 weather/field rules and duration remain engine-authoritative.
@MainActor
enum BattleFieldEffects {
    static let weather = ["sunnyday": "commonsunny", "raindance": "commonrain", "sandstorm": "commonsandstorm", "hail": "commonhail"]
    static let fields: Set<String> = ["trickroom", "gravity", "magicroom", "wonderroom", "mudsport", "watersport",
        "reflect", "lightscreen", "safeguard", "mist", "tailwind", "luckychant", "spikes", "stealthrock", "toxicspikes"]

    static let megaFields:Set<String> = ["electricterrain"]
    static let globalFields: Set<String> = ["electricterrain", "trickroom", "gravity", "magicroom", "wonderroom", "mudsport", "watersport"]
    static func isGlobal(_ event: BattleVisualEvent) -> Bool {
        event.phase == "field" && (weather.values.contains(event.moveID ?? event.move) || globalFields.contains(event.moveID ?? event.move))
    }

    struct Effect {
        let event: BattleVisualEvent
        let replacesMove: Int?
    }
    static func effect(scene: BattleScene, line: String, frame: BattleFrame) -> Effect? {
        let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 2 else { return nil }
        let kind = parts[1]
        let key: String
        var previous: BattleVisualEvent?
        if kind == "-weather" {
            guard let name = weather[BattleTextCatalog.key(parts[2])] else { return nil }
            key = name
        } else if kind == "-fieldstart" || kind == "-sidestart" || kind == "-start" {
            let argument = kind == "-fieldstart" ? 2 : 3
            guard parts.indices.contains(argument) else { return nil }
            let raw = parts[argument].components(separatedBy: ": ").last ?? ""
            let name = BattleTextCatalog.key(raw)
            guard fields.contains(name) || megaFields.contains(name) else { return nil }
            key = name
            let index = scene.id - (frame.logOffset ?? 0)
            if let moveIndex = frame.log.indices.last(where: { $0 < index && frame.log[$0].hasPrefix("|move|") }) {
                let id = (frame.logOffset ?? 0) + moveIndex
                previous = frame.effects?.first { $0.id == id && BattleTextCatalog.key($0.moveID ?? $0.move) == name }
            }
        } else { return nil }
        let source = previous?.source ?? BattleEffectPosition(own: true, slot: 0)
        return Effect(event: BattleVisualEvent(id: scene.id, move: key, type: "", category: "Status", source: source,
            targets: previous?.targets ?? [BattleEffectTarget(position: source, hit: true)], moveID: key, phase: "field"), replacesMove: previous?.id)
    }
}
