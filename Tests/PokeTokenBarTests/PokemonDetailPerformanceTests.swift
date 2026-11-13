import XCTest
@testable import PokeTokenBar

private struct DetailPerformanceProvider: PokeProviding, PokemonDetailProviding {
    let details: PokemonDetails
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails { details }
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class PokemonDetailPerformanceTests: XCTestCase {
    private func store(_ state: CompanionState, details: PokemonDetails) throws -> CompanionStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let suite = "detail-performance-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        return CompanionStore(provider: DetailPerformanceProvider(details: details), fileURL: file,
                              dittoDisguiseRollingEnabled: false, defaults: defaults)
    }

    func testFullLearnsetAndLargeCollectionUseOneSharedMoveTextTable() async throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "details", withExtension: "json", subdirectory: "ArceusDetails"))
        let details = try JSONDecoder().decode(PokemonDetails.self, from: Data(contentsOf: fixture))
        XCTAssertEqual(details.moves.count, 106)
        var state = CompanionState()
        for index in 0..<999 {
            let id = index % 648 + 1
            let speciesID = id == 493 ? 649 : id
            state.dex.append(.init(id: "fixture-\(index)", baseID: speciesID, finalID: speciesID,
                chainOrder: [speciesID], rarity: .common, caughtAt: Date(timeIntervalSince1970: Double(index))))
        }
        state.dex.append(.init(id: "arceus", baseID: 493, finalID: 493, chainOrder: [493],
            rarity: .legendary, caughtAt: Date(), form: PokemonForm("fire")))
        let store = try store(state, details: details)
        await store.loadPokemonDetails(speciesID: 493)
        let species = try XCTUnwrap(store.formSpecies(speciesID: 493).first)
        let start = ProcessInfo.processInfo.systemUptime
        let page = PokemonDetailView(store: store, species: species, onBack: {}).presentation
        let profile = try XCTUnwrap(page.individual?.profile)
        XCTAssertEqual(page.forms.count, 1)
        XCTAssertEqual(page.details?.types, ["fire"])
        XCTAssertEqual(page.moves.options.count, 108)
        XCTAssertEqual(page.moves.textByName.count, 108, "All four menus share one entry per move")
        let menus = (0..<4).map { page.moves.choices(profile: profile, slot: $0) }
        for menu in menus {
            XCTAssertEqual(menu.count, 108)
            for choice in menu {
                XCTAssertEqual(choice.title, page.moves.textByName[choice.id]?.title)
                XCTAssertEqual(choice.tooltip, page.moves.textByName[choice.id]?.tooltip)
            }
        }
        print("ARCEUS_LARGE_COLLECTION records=1000 options=108 snapshotAndMenusSeconds=\(ProcessInfo.processInfo.systemUptime - start)")
        XCTAssertEqual(store.pokemonDetailsByID[493], details)
    }

    /// Opt-in measurements read a copied save and write only to a separate temporary store.
    /// No timing thresholds: shared CI/desktop load must not make correctness tests flaky.
    func testCopiedSaveBenchmark() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let statePath = environment["PTB_DETAIL_BENCHMARK_STATE"],
              let detailsPath = environment["PTB_DETAIL_BENCHMARK_DETAILS"] else {
            throw XCTSkip("Opt-in copied-save performance measurement")
        }
        struct Snapshot: Decodable { let details: PokemonDetails }
        let state = try JSONDecoder().decode(CompanionState.self, from: Data(contentsOf: URL(fileURLWithPath: statePath)))
        let details = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: URL(fileURLWithPath: detailsPath))).details
        let store = try store(state, details: details)
        await store.loadPokemonDetails(speciesID: 493)
        let species = try XCTUnwrap(store.formSpecies(speciesID: 493).first)
        let view = PokemonDetailView(store: store, species: species, onBack: {})
        let savedProfiles = store.state.dex.map(\.profile)
        var seconds: [Double] = [], checksum = 0, count = 0
        for _ in 0..<5 {
            let start = ProcessInfo.processInfo.systemUptime
            let page = view.presentation
            let profile = try XCTUnwrap(page.individual?.profile)
            count = page.moves.options.count
            for slot in 0..<4 {
                for choice in page.moves.choices(profile: profile, slot: slot) {
                    checksum += choice.title.count + choice.tooltip.count
                }
            }
            seconds.append(ProcessInfo.processInfo.systemUptime - start)
        }
        print("ARCEUS_AFTER records=\(store.state.dex.count) options=\(count) menuCount=4 samples=\(seconds) medianSeconds=\(seconds.sorted()[2]) checksum=\(checksum)")
        XCTAssertEqual(store.state.dex.map(\.profile), savedProfiles)
        XCTAssertEqual(store.pokemonDetailsByID[493], details)
        XCTAssertGreaterThan(checksum, 0)
    }
}
