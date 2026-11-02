import Foundation

/// A cosmetic, fixed arena chosen from the opponent's registered species types.
enum BattleArena: String, CaseIterable, Sendable {
    case plains, forest, snowyForest = "snowy_forest"
    case sea, beach, lake
    case mountain, desert, volcano
    case cave, iceCave = "ice_cave", fairyCave = "fairy_cave"
    case town, metropolis, dojo
    case end

    var group: String {
        switch self {
        case .plains, .forest, .snowyForest: "woods"
        case .sea, .beach, .lake: "water"
        case .mountain, .desert, .volcano: "highlands"
        case .cave, .iceCave, .fairyCave: "caves"
        case .town, .metropolis, .dojo: "settlements"
        case .end: "special"
        }
    }
    var backgroundPath: String { "images/arenas/\(rawValue)_bg.png" }

    // Explicit priority makes mixed-team ties stable across processes and selection order.
    static let typeOrder=["normal","fire","water","electric","grass","ice","fighting","poison","ground","flying","psychic","bug","rock","ghost","dragon","dark","steel","fairy"]
    static let typeArenas:[String:Self]=[
        "normal":.plains,"fire":.volcano,"water":.lake,"electric":.metropolis,
        "grass":.forest,"ice":.iceCave,"fighting":.dojo,"poison":.forest,
        "ground":.desert,"flying":.mountain,"psychic":.fairyCave,"bug":.forest,
        "rock":.mountain,"ghost":.cave,"dragon":.mountain,"dark":.cave,
        "steel":.metropolis,"fairy":.fairyCave
    ]
    static func forTypes(_ types:[String])->Self {
        let counts=Dictionary(grouping:types,by:{$0}).mapValues(\.count)
        var selected:String?,best=0
        for type in typeOrder {
            let count=counts[type] ?? 0
            if count>best {selected=type;best=count}
        }
        return selected.flatMap{typeArenas[$0]} ?? .plains
    }
    @MainActor static func forChallenge(encounterID:String?,roster:[BattleRosterMember])->Self {
        encounterID=="red" ? .end:forOpponent(roster)
    }
    @MainActor static func forOpponent(_ roster:[BattleRosterMember])->Self {
        forTypes(roster.flatMap{member in
            BattleHeldItems.mega(speciesID:member.speciesID,form:member.form)?.types
                ?? BattleTextCatalog.shared.pokemonTypes(member.speciesID,form:member.form)
        })
    }
}
