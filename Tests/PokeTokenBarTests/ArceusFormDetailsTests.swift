import AppKit
import XCTest
@testable import PokeTokenBar

private let arceusDetails = PokemonDetails(
    speciesID: 493, name: "arceus", height: 32, weight: 3200,
    baseExperience: 324, genderRate: -1, types: ["normal"],
    baseStats: Dictionary(uniqueKeysWithValues: PokemonStatCalculator.order.map { ($0, 120) }),
    abilities: [.init(name: "multitype", slot: 1, isHidden: false)],
    moves: [
        .init(name: "judgment", learnMethods: [.init(method: "level-up", level: 100)]),
        .init(name: "earth-power", learnMethods: [.init(method: "level-up", level: 20)]),
        .init(name: "recover", learnMethods: [.init(method: "level-up", level: 70)])])

private struct ArceusDetailProvider: PokeProviding, PokemonDetailProviding {
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails { arceusDetails }
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 493, tree: EvoNode(speciesID: 493, children: []), rarity: .legendary,
                names: [493: ["en": "Arceus", "ko": "아르세우스"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

final class ArceusFormDetailsTests: XCTestCase {
    @MainActor
    private func store(_ state: CompanionState) throws -> CompanionStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let suite = "arceus-snapshot-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        return CompanionStore(provider: ArceusDetailProvider(), fileURL: file,
                              dittoDisguiseRollingEnabled: false, defaults: defaults)
    }

    @MainActor
    func testTypeLabelsAreBundledInEveryLanguageWithoutFormRequests() {
        XCTAssertTrue(PokemonForm.nameResources(speciesID: 493).isEmpty)
        for form in PokemonForm.forms(speciesID: 493) {
            XCTAssertNil(PokemonForm.nameResource(speciesID: 493, form: form))
            for language in AppLanguage.allCases {
                let type = BattleTextCatalog.shared.typeName(form.rawValue, language: language)
                XCTAssertNotEqual(type, L(language).battleUnknownType)
                XCTAssertEqual(PokemonForm.label(speciesID: 493, form: form, language: language), type)
            }
        }
    }

    func testMoveTextIsSharedAcrossSlotsAndRebuiltForFormLanguageLevelAndMoves() throws {
        var profile = PokemonProfile.generate(seed: 27)
        profile.level = 100
        profile.enrich(with: arceusDetails)
        let fire = PokemonDetailMoves(details: arceusDetails, profile: profile,
            speciesID: 493, form: PokemonForm("fire"), language: .en)
        XCTAssertEqual(fire.textByName.count, Set(fire.all.map(\.name)).count)
        for slot in 0..<4 {
            for choice in fire.choices(profile: profile, slot: slot) {
                XCTAssertEqual(choice.title, fire.textByName[choice.id]?.title)
                XCTAssertEqual(choice.tooltip, fire.textByName[choice.id]?.tooltip)
                XCTAssertEqual(choice.selected, profile.moves.indices.contains(slot) && profile.moves[slot].name == choice.id)
                XCTAssertEqual(choice.enabled, !profile.moves.enumerated().contains { $0.offset != slot && $0.element.name == choice.id })
            }
        }
        let water = PokemonDetailMoves(details: arceusDetails, profile: profile,
            speciesID: 493, form: PokemonForm("water"), language: .ko)
        XCTAssertTrue(fire.text("judgment").title.contains("Fire"))
        XCTAssertTrue(water.text("judgment").title.contains("물"))
        XCTAssertTrue(water.text("earth-power").title.contains("땅"))
        profile.level = 5
        profile.moves = [.init(name: "recover", learnedAtLevel: 70)]
        let lowLevel = PokemonDetailMoves(details: arceusDetails, profile: profile,
            speciesID: 493, form: PokemonForm("water"), language: .ko)
        XCTAssertFalse(lowLevel.options.contains { $0.name == "judgment" })
        XCTAssertEqual(lowLevel.choices(profile: profile, slot: 0).map(\.id), lowLevel.options.map(\.name))
        // Historical/custom moves remain displayable even when absent from the current learnset.
        profile.moves = [.init(name: "tackle", learnedAtLevel: 1)]
        let legacy = PokemonDetailMoves(details: arceusDetails, profile: profile,
            speciesID: 493, form: nil, language: .en)
        XCTAssertNotNil(legacy.textByName["tackle"])
        let loading = PokemonDetailMoves(details: nil, profile: nil, speciesID: 493, form: nil, language: .en)
        XCTAssertTrue(loading.all.isEmpty)
        XCTAssertTrue(loading.options.isEmpty)
        XCTAssertEqual(loading.text("recover").title, BattleTextCatalog.shared.moveMenuTitle("recover", language: .en))
    }

    @MainActor
    func testSnapshotsFollowTypeAppearanceIndividualLanguageAndLoadoutEdits() async throws {
        var state = CompanionState()
        state.dex = [
            .init(id: "fire-a", baseID: 493, finalID: 493, chainOrder: [493], rarity: .legendary, caughtAt: Date(), form: PokemonForm("fire")),
            .init(id: "fire-b", baseID: 493, finalID: 493, chainOrder: [493], rarity: .legendary, caughtAt: Date(), isShiny: true, form: PokemonForm("fire")),
            .init(id: "water", baseID: 493, finalID: 493, chainOrder: [493], rarity: .legendary, caughtAt: Date(), form: PokemonForm("water"))]
        let store = try store(state)
        await store.loadPokemonDetails(speciesID: 493)
        let species = try XCTUnwrap(store.formSpecies(speciesID: 493).first)
        func snapshot(_ form: String, shiny: Bool = false, id: String = "") -> PokemonDetailPresentation {
            PokemonDetailPresentation(store: store, species: species, selectedForm: PokemonForm(form),
                selectedShiny: shiny, selectedInstanceID: id)
        }
        let fire = snapshot("fire", id: "fire-a")
        XCTAssertEqual(fire.individual?.id, "fire-a")
        XCTAssertEqual(fire.individuals.map(\.id), ["fire-a"])
        XCTAssertEqual(snapshot("fire", shiny: true).individual?.id, "fire-b")
        XCTAssertEqual(snapshot("water").individual?.id, "water")
        XCTAssertEqual(snapshot("water").details?.types, ["water"])
        let profile = try XCTUnwrap(fire.individual?.profile)
        let replacement = try XCTUnwrap(fire.moves.options.first { option in !profile.moves.contains { $0.name == option.name } })
        XCTAssertTrue(store.setPokemonMove(entryID: "fire-a", slot: 0, name: replacement.name))
        store.setLanguage(.ko)
        let changed = snapshot("fire", id: "fire-a")
        XCTAssertEqual(changed.individual?.profile?.moves.first?.name, replacement.name)
        XCTAssertEqual(changed.individual?.profile?.ivs, profile.ivs)
        XCTAssertTrue(changed.moves.text("judgment").title.contains("불꽃"))
        XCTAssertEqual(store.pokemonDetailsByID[493], arceusDetails)
        XCTAssertEqual(fire.individual?.profile?.moves, profile.moves,
                       "Editing the store must not mutate an already captured presentation")
    }

    @MainActor
    func testNativeMoveMenuIsReusedUntilItsVisibleContentsChange() throws {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        let coordinator = PokemonLoadoutPicker.Coordinator(onSelect: { _ in })
        let choices = [PokemonLoadoutChoice(id: "judgment", title: "Judgment · Fire", tooltip: "Special")]
        coordinator.configure(button, title: "Move", tooltip: "Details", choices: choices)
        let first = try XCTUnwrap(button.menu)
        coordinator.configure(button, title: "Move", tooltip: "Details", choices: choices)
        XCTAssertTrue(button.menu === first)
        var changed = choices
        changed[0].selected = true
        changed[0].enabled = false
        coordinator.configure(button, title: "기술", tooltip: "설명", choices: changed)
        XCTAssertFalse(button.menu === first)
        XCTAssertEqual(button.menu?.item(at: 1)?.state, .on)
        XCTAssertEqual(button.menu?.item(at: 1)?.isEnabled, false)
        XCTAssertEqual(button.toolTip, "설명")
    }

    @MainActor
    func testEvolutionReferenceKeepsCollectedAppearanceWithoutAnExactIndividual() throws {
        var state = CompanionState()
        state.dex = [.init(baseID: 412, finalID: 413, chainOrder: [412, 413], rarity: .common,
                           caughtAt: Date(), isShiny: true, form: PokemonForm("plant"))]
        let store = try store(state)
        let species = try XCTUnwrap(store.formSpecies(speciesID: 412).first)
        // This is the reached pre-evolution's information page, not an owned final individual.
        for selectedShiny in [nil, false] as [Bool?] {
            let page = PokemonDetailPresentation(store: store, species: species, selectedForm: nil,
                selectedShiny: selectedShiny, selectedInstanceID: "")
            XCTAssertTrue(page.shiny)
            XCTAssertTrue(page.individuals.isEmpty)
            XCTAssertNil(page.individual)
            XCTAssertNil(page.details)
            XCTAssertTrue(page.moves.options.isEmpty)
        }
    }
    func testAllEighteenTypesShareStatsAbilityAndLearnset() {
        let forms = PokemonForm.forms(speciesID: 493)
        XCTAssertEqual(forms.count, 18)
        for form in forms {
            let details = arceusDetails.displayed(form: form)
            XCTAssertEqual(details.types, [form.rawValue])
            XCTAssertEqual(details.baseStats, arceusDetails.baseStats)
            XCTAssertEqual(details.baseStatTotal, 720)
            XCTAssertEqual(details.abilities, arceusDetails.abilities)
            XCTAssertEqual(details.moves, arceusDetails.moves)
            XCTAssertEqual(details.height, 32)
            XCTAssertEqual(details.weight, 3200)
        }
        XCTAssertEqual(arceusDetails.types, ["normal"], "Presentation must not mutate cached metadata")
        XCTAssertEqual(arceusDetails.displayed(form: nil), arceusDetails)
        XCTAssertEqual(arceusDetails.displayed(form: PokemonForm("invalid")), arceusDetails)
        let pikachu = PokemonDetails(speciesID: 25, name: "pikachu", height: 4, weight: 60,
            baseExperience: 112, genderRate: 4, types: ["electric"], baseStats: [:], abilities: [], moves: [])
        XCTAssertEqual(pikachu.displayed(form: PokemonForm("fire")), pikachu)
    }

    func testJudgmentUsesFormTypeInLocalizedTitlesAndTooltipsOnly() {
        let catalog = BattleTextCatalog.shared
        for form in PokemonForm.forms(speciesID: 493) {
            XCTAssertEqual(catalog.moveType("Judgment", speciesID: 493, form: form), form.rawValue)
            for language in AppLanguage.allCases {
                let type = catalog.typeName(form.rawValue, language: language)
                let title = catalog.moveMenuTitle("judgment", language: language, speciesID: 493, form: form)
                let tooltip = catalog.moveTooltip("judgment", language: language, speciesID: 493, form: form)
                XCTAssertTrue(title.contains(" · " + type + " · "), title)
                XCTAssertTrue(tooltip.contains(type + " · "), tooltip)
                XCTAssertTrue(tooltip.contains("100"))
                XCTAssertTrue(tooltip.contains("10"))
            }
            XCTAssertEqual(catalog.moveType("earth-power", speciesID: 493, form: form), "ground")
            XCTAssertEqual(catalog.moveType("recover", speciesID: 493, form: form), "normal")
        }
        XCTAssertEqual(catalog.moveType("judgment"), "normal")
        XCTAssertEqual(catalog.moveType("judgment", speciesID: 25, form: PokemonForm("fire")), "normal")
    }

    @MainActor
    func testDetailPageProjectsOwnedFormInsteadOfDefaultCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "arceus-details-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for form in PokemonForm.forms(speciesID: 493) {
            let url = directory.appendingPathComponent(form.rawValue + ".json")
            var state = CompanionState()
            state.dex = [.init(baseID: 493, finalID: 493, chainOrder: [493], rarity: .legendary,
                               caughtAt: Date(), form: form)]
            try JSONEncoder().encode(state).write(to: url)
            let store = CompanionStore(provider: ArceusDetailProvider(), fileURL: url,
                dittoDisguiseRollingEnabled: false, defaults: defaults)
            await store.loadPokemonDetails(speciesID: 493)
            let species = try XCTUnwrap(store.formSpecies(speciesID: 493).first)
            let page = PokemonDetailView(store: store, species: species, onBack: {}).presentation
            XCTAssertEqual(page.details?.types, [form.rawValue])
            let type = BattleTextCatalog.shared.typeName(form.rawValue, language: store.language)
            XCTAssertTrue(page.moves.text("judgment").title.contains(" · " + type + " · "))
            XCTAssertTrue(page.moves.text("judgment").tooltip.contains(type + " · "))
            XCTAssertEqual(store.pokemonDetailsByID[493], arceusDetails)
            XCTAssertEqual(store.state.dex.first?.form, form)
        }
    }
}
