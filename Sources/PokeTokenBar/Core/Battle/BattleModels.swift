import Foundation

enum BattleMode: String, Codable, CaseIterable, Sendable {
    case singles, doubles
    var teamSize: Int { 6 }
    var battleSize: Int { self == .singles ? 3 : 4 }
}

struct BattlePokemon: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let speciesID: Int
    let species: String
    let displayName: String
    let level: Int
    var ability: String
    var abilitySlot: Int? = nil
    let nature: String
    let gender: String
    let shiny: Bool
    let form: PokemonForm?
    let ivs: [String: Int]
    let stats: [String: Int]
    let moves: [String]
    var item: String? = nil
}

/// The public six-member preview intentionally has no moves, ability, IVs or stats.
struct BattleRosterMember: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let speciesID: Int
    let level: Int
    let shiny: Bool
    let form: PokemonForm?
    init(_ pokemon: BattlePokemon) {
        id = pokemon.id; speciesID = pokemon.speciesID; level = pokemon.level
        shiny = pokemon.shiny; form = pokemon.form
    }
}

struct BattleTarget: Codable, Sendable, Hashable { let location: Int; let name: String }
struct BattleMatchup: Codable, Sendable {
    let location: Int
    let name: String
    let multiplier: Double?
}
enum BattleMoveAccuracy: Codable, Sendable, Equatable {
    case percent(Int)
    case always

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if (try? value.decode(Bool.self)) == true { self = .always }
        else { self = .percent(try value.decode(Int.self)) }
    }
    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .always: try value.encode(true)
        case .percent(let percent): try value.encode(percent)
        }
    }
}
struct BattleMove: Codable, Sendable, Identifiable {
    var id: Int { index }
    let index: Int
    let name: String
    let apiName: String?
    let pp: Int
    let maxPP: Int
    let disabled: Bool
    let type: String
    let power: Int?
    let category: String?
    let description: String?
    let matchups: [BattleMatchup]?
    let targetRequired: Bool
    let targets: [BattleTarget]
    var targetScope: String? = nil
    var accuracy: BattleMoveAccuracy? = nil
}
struct BattleSlot: Codable, Sendable, Identifiable {
    var id: Int { slot }
    let slot: Int
    let mustSwitch: Bool
    let canPass: Bool
    let trapped: Bool
    let moves: [BattleMove]
    var canMegaEvo: Bool? = nil
}
struct BattleCombatant: Codable, Sendable, Identifiable {
    let id: String
    let speciesID: Int
    let name: String
    let level: Int
    let shiny: Bool
    let active: Bool
    let form: PokemonForm?
    let fainted: Bool
    let hp: Int
    let maxHP: Int
    let status: String
    let stats: [String: Int]?
    var boosts: [String: Int]? = nil
    var ability: String? = nil
    var item: String? = nil
    var mega: Bool? = nil
}
struct BattleEffectPosition: Codable, Sendable, Hashable {
    let own: Bool
    let slot: Int
    static func key(own: Bool, slot: Int) -> String { "\(own ? "own" : "foe")-\(slot)" }
    var key: String { Self.key(own:own,slot:slot) }
}
struct BattleEffectTarget: Codable, Sendable, Hashable {
    let position: BattleEffectPosition
    let hit: Bool
}
struct BattleVisualEvent: Codable, Sendable, Identifiable, Hashable {
    let id: Int
    let move: String
    let type: String
    let category: String
    let source: BattleEffectPosition
    let targets: [BattleEffectTarget]
    var moveID: String? = nil
    var phase: String? = nil
}
/// Seeded from the current frame so reopening/reconnecting does not replay old turns.
struct BattleEffectCursor {
    private(set) var lastSeen: Int
    init(events: [BattleVisualEvent]) { lastSeen = events.last?.id ?? -1 }
    mutating func takeNew(_ events: [BattleVisualEvent]) -> [BattleVisualEvent] {
        let pending = events.filter { $0.id > lastSeen }
        lastSeen = max(lastSeen,events.last?.id ?? -1)
        return pending
    }
}
struct BattleFieldTiming: Codable, Sendable, Equatable {
    let remaining: Int
    let maximum: Int
    var label: String { "\(remaining)/\(maximum)" }
}
struct BattleFieldCondition: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let layers: Int
    var timing: BattleFieldTiming? = nil
}
struct BattleFieldState: Codable, Sendable, Equatable {
    let weather: String
    let weatherSuppressed: Bool
    let conditions: [String]
    let ownSide: [BattleFieldCondition]
    let foeSide: [BattleFieldCondition]
    var weatherTiming: BattleFieldTiming? = nil
    var conditionTimings: [String: BattleFieldTiming]? = nil
    var isEmpty: Bool { weather.isEmpty && conditions.isEmpty && ownSide.isEmpty && foeSide.isEmpty }
}
/// Immutable public state at an executed protocol event, never the opponent's private team.
struct BattleScene: Codable, Sendable, Identifiable {
    let id: Int
    let turn: Int
    let own: [BattleCombatant]
    let foe: [BattleCombatant]
    let field: BattleFieldState
}
struct BattleFrame: Codable, Sendable {
    let revision: String
    let turn: Int
    let decisionID: String
    let preview: Bool
    let waiting: Bool
    let own: [BattleCombatant]
    let foe: [BattleCombatant]
    let slots: [BattleSlot]
    let log: [String]
    var effects: [BattleVisualEvent]? = nil
    var field: BattleFieldState? = nil
    var logOffset: Int? = nil
    var scenes: [BattleScene]? = nil
    let ended: Bool
    let winner: Int?
}
struct BattleAction: Codable, Sendable, Hashable {
    let kind: String
    let index: Int
    let target: Int
    var mega: Bool? = nil
    static let pass = BattleAction(kind: "pass", index: 0, target: 0)
}
/// One trainer may arm only one active slot; switching/passing never requests evolution.
struct BattleMegaSelection:Sendable {
    private(set) var slot:Int? = nil
    mutating func set(_ selected:Bool,slot:Int) {
        if selected {self.slot=slot} else if self.slot==slot {self.slot=nil}
    }
    func applying(to action:BattleAction,slot:Int,canMega:Bool)->BattleAction {
        var command=action
        command.mega=action.kind=="move" && self.slot==slot && canMega ? true:nil
        return command
    }
}
struct BattleDecision: Codable, Sendable {
    let decisionID: String
    let actions: [BattleAction]
    let order: [Int]
}

enum BattleFailure: LocalizedError {
    case invalidTeam(String), unavailableEngine, invalidMessage
    var errorDescription: String? {
        switch self {
        case .invalidTeam(let reason): reason
        case .unavailableEngine: "Battle engine is unavailable. Rebuild the app with scripts/prepare-battle-engine.sh."
        case .invalidMessage: "Incompatible battle message. Update both apps to the same version."
        }
    }
}

enum BattleTeamBuilder {
    static func orderedRoster(_ roster: [String], lineup: [String], mode: BattleMode) throws -> [String] {
        guard roster.count == mode.teamSize, Set(roster).count == roster.count,
              lineup.count == mode.battleSize, Set(lineup).count == lineup.count,
              lineup.allSatisfy({ roster.contains($0) }) else {
            throw BattleFailure.invalidTeam("Invalid battle lineup")
        }
        return lineup + roster.filter { !lineup.contains($0) }
    }
    static let statNames = ["hp": "hp", "attack": "atk", "defense": "def", "special-attack": "spa", "special-defense": "spd", "speed": "spe"]
    // Generation V: Arceus (including Normal) depends on held plates for its type.
    static func isSpeciesEligible(_ speciesID: Int) -> Bool { speciesID != 493 }

    static let finalSpeciesIDs: Set<Int> = {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("BattleText/final-species.json")
        let url = bundled.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            ?? Bundle.module.url(forResource: "final-species", withExtension: "json", subdirectory: "BattleText")!
        return Set(try! JSONDecoder().decode([Int].self, from: Data(contentsOf: url)))
    }()
    static func isFinalEvolution(_ speciesID: Int) -> Bool { finalSpeciesIDs.contains(speciesID) }

    /// Call with state.dex: those are graduation/release records, never the synthetic active entry.
    static func storedCandidates(_ entries: [DexEntry]) -> [DexEntry] {
        entries.filter { !$0.isReleased && $0.profile != nil && isFinalEvolution($0.finalID) }
    }

    static func hasSelectedSpecies(_ entry: DexEntry, selectedIDs: [String], entries: [DexEntry]) -> Bool {
        entries.contains { selectedIDs.contains($0.id) && $0.id != entry.id && $0.finalID == entry.finalID }
    }

    @MainActor
    static func build(ids: [String], entries: [DexEntry], mode: BattleMode,
                      language: AppLanguage, provider: any PokemonDetailProviding = PokeAPIClient.shared,
                      heldItems:[String:String]=[:]) async throws -> [BattlePokemon] {
        guard ids.count == mode.teamSize, Set(ids).count == ids.count else {
            throw BattleFailure.invalidTeam("Select exactly \(mode.teamSize) different individuals.")
        }
        var speciesIDs = Set<Int>()
        for id in ids {
            guard let entry = entries.first(where: { $0.id == id && !$0.isReleased }), entry.profile != nil else {
                throw BattleFailure.invalidTeam("This Pokémon is no longer available.")
            }
            guard isFinalEvolution(entry.finalID) else {
                throw BattleFailure.invalidTeam(L(language).battleFinalOnly)
            }
            guard isSpeciesEligible(entry.finalID) else {
                throw BattleFailure.invalidTeam(L(language).battleItemTypeExcluded)
            }
            guard speciesIDs.insert(entry.finalID).inserted else {
                throw BattleFailure.invalidTeam(L(language).battleDuplicateSpecies)
            }
        }
        var team: [BattlePokemon] = []
        for id in ids {
            guard let entry = entries.first(where: { $0.id == id && !$0.isReleased }), var profile = entry.profile else {
                throw BattleFailure.invalidTeam("This Pokémon is no longer available.")
            }
            guard isSpeciesEligible(entry.finalID) else {
                throw BattleFailure.invalidTeam(L(language).battleItemTypeExcluded)
            }
            let details = try await provider.pokemonDetails(speciesID: entry.finalID)
            // Refresh historical ability compatibility even when a legacy saved loadout is complete.
            let savedMoves = profile.moves
            profile.enrich(with: details, form: entry.form)
            if !savedMoves.isEmpty { profile.moves = savedMoves }
            guard !profile.moves.isEmpty, let ability = profile.abilityName else {
                throw BattleFailure.invalidTeam("Open this Pokémon's Pokédex details to load its ability and moves first.")
            }
            let values = PokemonStatCalculator.stats(details: details, profile: profile, nature: entry.nature)
            let stats = Dictionary(uniqueKeysWithValues: values.compactMap { value -> (String, Int)? in
                guard let key = statNames[value.name] else { return nil }; return (key, value.value)
            })
            let ivs = Dictionary(uniqueKeysWithValues: statNames.map { ($0.value, profile.ivs[$0.key]) })
            let resolved = PokemonForm.resolved(speciesID: entry.finalID, form: entry.form)
            let species = engineSpecies(details.name, speciesID: entry.finalID, form: resolved)
            team.append(BattlePokemon(id: entry.id, speciesID: entry.finalID, species: species,
                displayName: entry.names?[entry.finalID].flatMap { language.resolveName($0) } ?? details.name,
                level: profile.level, ability: ability, abilitySlot: profile.abilitySlot, nature: entry.nature?.rawValue ?? "hardy",
                gender: profile.gender == .male ? "M" : profile.gender == .female ? "F" : "",
                shiny: entry.isShiny, form: resolved, ivs: ivs, stats: stats, moves: profile.moves.map(\.name),item:heldItems[entry.id]))
        }
        guard !BattleHeldItems.hasDuplicates(team) else {throw BattleFailure.invalidTeam(L(language).battleDuplicateItem)}
        let abilities = try await BattleEngineProcess.validate(mode: mode, team: team)
        guard abilities.count == team.count else { throw BattleFailure.invalidMessage }
        for index in team.indices { team[index].ability = abilities[index] }
        return team
    }

    static func engineSpecies(_ name: String, speciesID: Int, form: PokemonForm?) -> String {
        let baseNames = [201: "Unown", 351: "Castform", 386: "Deoxys", 412: "Burmy", 413: "Wormadam", 421: "Cherrim", 422: "Shellos", 423: "Gastrodon", 479: "Rotom", 487: "Giratina", 492: "Shaymin", 493: "Arceus", 550: "Basculin", 555: "Darmanitan", 585: "Deerling", 586: "Sawsbuck"]
        let name = baseNames[speciesID] ?? name
        guard let form, let first = PokemonForm.forms(speciesID: speciesID).first, form != first else { return name }
        let aliases = ["sandy": "Sandy", "trash": "Trash", "sunny": "Sunny", "snowy": "Snowy", "rainy": "Rainy", "east": "East", "sunshine": "Sunshine", "exclamation": "!", "question": "?"]
        // Shellos/Gastrodon east and seasonal Deerling are cosmetic forms in the simulator.
        if [422,423,585,586].contains(speciesID) { return name }
        return "\(name)-\(aliases[form.rawValue] ?? form.rawValue)"
    }
}
