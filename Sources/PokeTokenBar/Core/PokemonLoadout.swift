import Foundation

/// Choices are scoped to the exact owned individual. Nature, IVs and level have no edit path.
enum PokemonLoadout {
    static let abilities: [String: [PokemonAbilityOption]] = {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("BattleText/ability-options.json")
        let url = bundled.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            ?? Bundle.module.url(forResource: "ability-options", withExtension: "json", subdirectory: "BattleText")!
        return try! JSONDecoder().decode([String: [PokemonAbilityOption]].self, from: Data(contentsOf: url))
    }()

    static func abilityOptions(details: PokemonDetails, form: PokemonForm?) -> [PokemonAbilityOption] {
        let species = BattleTeamBuilder.engineSpecies(details.name, speciesID: details.speciesID, form: form)
        return abilities[BattleTextCatalog.key(species)] ?? []
    }

    static func moveOptions(details: PokemonDetails, level: Int) -> [PokemonKnownMove] {
        PokemonFairyMoves.mergedMoves(details:details).compactMap { move in
            let methods = move.learnMethods.filter { $0.method != "level-up" || $0.level <= level }
            guard !methods.isEmpty else { return nil }
            return PokemonKnownMove(name: move.name, learnedAtLevel: methods.map(\.level).min() ?? 0)
        }.sorted { $0.name < $1.name }
    }

    static func replacingMove(_ profile: PokemonProfile, slot: Int, name: String,
                              details: PokemonDetails) -> PokemonProfile? {
        guard slot >= 0, slot < 4, slot <= profile.moves.count,
              let move = moveOptions(details: details, level: profile.level).first(where: { $0.name == name }),
              !profile.moves.enumerated().contains(where: { $0.offset != slot && $0.element.name == name }) else { return nil }
        var updated = profile
        if slot == updated.moves.count { updated.moves.append(move) } else { updated.moves[slot] = move }
        updated.hasCustomMoves = true
        return updated
    }
}
