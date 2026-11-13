import Foundation

/// One immutable snapshot per body evaluation. Row builders never re-enter the collection store.
@MainActor
struct PokemonDetailPresentation {
    let forms: [CompanionStore.DexSpecies]
    let species: CompanionStore.DexSpecies
    let shiny: Bool
    let individuals: [DexEntry]
    let individual: DexEntry?
    let details: PokemonDetails?
    let moves: PokemonDetailMoves

    init(store: CompanionStore, species fallback: CompanionStore.DexSpecies,
         selectedForm: PokemonForm?, selectedShiny: Bool?, selectedInstanceID: String) {
        let forms = store.formSpecies(speciesID: fallback.id)
        let species = forms.first { $0.form == selectedForm }
            ?? forms.first { store.isRepresentative($0) } ?? forms.first ?? fallback
        let all = store.pokemonIndividuals(speciesID: fallback.id, form: species.form)
        let shiny: Bool
        if let selectedShiny, selectedShiny ? species.isShiny : species.hasNormal {
            shiny = selectedShiny
        } else {
            shiny = all.first?.isShiny ?? species.isShiny
        }
        let individuals = all.filter { $0.isShiny == shiny }
        let individual = individuals.first { $0.id == selectedInstanceID } ?? individuals.first
        let details = store.pokemonDetailsByID[fallback.id]?.displayed(form: species.form)
        self.forms = forms
        self.species = species
        self.shiny = shiny
        self.individuals = individuals
        self.individual = individual
        self.details = details
        moves = PokemonDetailMoves(details: details, profile: individual?.profile,
            speciesID: fallback.id, form: species.form, language: store.language)
    }
}

/// All four move menus and the learnset share the same localized strings.
/// Rebuilt with the view snapshot so form, language, level and loadout edits cannot go stale.
struct PokemonDetailMoves {
    struct Text: Equatable {
        let title: String
        let tooltip: String
    }
    let all: [PokemonMoveOption]
    let options: [PokemonKnownMove]
    let textByName: [String: Text]
    private let speciesID: Int
    private let form: PokemonForm?
    private let language: AppLanguage

    init(details: PokemonDetails?, profile: PokemonProfile?, speciesID: Int,
         form: PokemonForm?, language: AppLanguage) {
        self.speciesID = speciesID
        self.form = form
        self.language = language
        let catalog = BattleTextCatalog.shared
        all = details.map { PokemonFairyMoves.mergedMoves(details: $0) } ?? []
        if let details, let profile {
            options = PokemonLoadout.moveOptions(details: details, level: profile.level).sorted {
                catalog.moveName($0.name, language: language)
                    .localizedStandardCompare(catalog.moveName($1.name, language: language)) == .orderedAscending
            }
        } else {
            options = []
        }
        let names = Set(all.map(\.name) + (profile?.moves.map(\.name) ?? []))
        textByName = Dictionary(uniqueKeysWithValues: names.map { name in
            (name, Self.text(name, speciesID: speciesID, form: form, language: language))
        })
    }

    func text(_ name: String) -> Text {
        textByName[name] ?? Self.text(name, speciesID: speciesID, form: form, language: language)
    }

    func choices(profile: PokemonProfile, slot: Int) -> [PokemonLoadoutChoice] {
        options.map { move in
            let text = text(move.name)
            return PokemonLoadoutChoice(id: move.name, title: text.title, tooltip: text.tooltip,
                selected: profile.moves.indices.contains(slot) && profile.moves[slot].name == move.name,
                enabled: !profile.moves.enumerated().contains { $0.offset != slot && $0.element.name == move.name })
        }
    }

    private static func text(_ name: String, speciesID: Int, form: PokemonForm?, language: AppLanguage) -> Text {
        let catalog = BattleTextCatalog.shared
        return Text(title: catalog.moveMenuTitle(name, language: language, speciesID: speciesID, form: form),
                    tooltip: catalog.moveTooltip(name, language: language, speciesID: speciesID, form: form))
    }
}
