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
            let page = PokemonDetailView(store: store, species: species, onBack: {})
            XCTAssertEqual(page.displayedDetails?.types, [form.rawValue])
            let type = BattleTextCatalog.shared.typeName(form.rawValue, language: store.language)
            XCTAssertTrue(page.moveMenuTitle("judgment").contains(" · " + type + " · "))
            XCTAssertTrue(page.moveTooltip("judgment").contains(type + " · "))
            XCTAssertEqual(store.pokemonDetailsByID[493], arceusDetails)
            XCTAssertEqual(store.state.dex.first?.form, form)
        }
    }
}
