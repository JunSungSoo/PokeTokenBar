import Foundation

enum SafariArea: String, Codable, CaseIterable, Sendable {
    case plains, forest, lake, mountain, desert, volcano, metropolis, dojo, cave
    case fairyCave = "fairy_cave", iceCave = "ice_cave"
}

struct SafariSpecies: Codable, Sendable, Equatable, Identifiable {
    let id: Int
    let area: SafariArea
    let types: [String]
    let bst: Int
    let legendary: Bool
    let captureRate: Int
    var rarity: Rarity { .from(captureRate: captureRate, isLegendary: legendary, isMythical: false) }
    var catchChance: Double { SafariCaptureOdds(captureRate:captureRate).successProbability*100 }
    var fleeChance: Double { bst >= 600 ? 40 : 25 }
}

struct SafariCatalog: Sendable {
    let species: [SafariSpecies]
    static func load() throws -> Self {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("BattleText/safari-species.json")
        let url = bundled.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            ?? AppResources.module.url(forResource: "safari-species", withExtension: "json", subdirectory: "BattleText")
        guard let url else { throw SafariError.catalog }
        let result = Self(species: try JSONDecoder().decode([SafariSpecies].self, from: Data(contentsOf: url)))
        try result.validate()
        return result
    }
    func validate() throws {
        let allowed: [SafariArea: Set<String>] = [
            .plains: ["normal"], .forest: ["grass", "bug", "poison"], .lake: ["water"],
            .mountain: ["rock", "dragon", "flying"], .desert: ["ground"], .volcano: ["fire"],
            .metropolis: ["electric", "steel"], .dojo: ["fighting"], .cave: ["ghost", "dark"],
            .fairyCave: ["psychic"], .iceCave: ["ice"]]
        guard species.count == 221, Set(species.map(\.id)).count == 221,
              Set(species.filter(\.legendary).map(\.id)) == [144,145,146,249,250],
              SafariArea.allCases.allSatisfy({ area in species.filter { $0.area == area }.count >= 15 }),
              species.allSatisfy({ (1...649).contains($0.id) && $0.bst > 0 &&
                  !Set($0.types).isDisjoint(with: allowed[$0.area] ?? []) && ($0.area != .forest || $0.bst >= 400) })
        else { throw SafariError.catalog }
    }
    /// Stable area mascot: legendary first, then BST, catch rarity and Pokédex number.
    func representative(in area: SafariArea) -> SafariSpecies? {
        species.filter { $0.area == area }.sorted { a, b in
            if a.legendary != b.legendary { return a.legendary }
            if a.bst != b.bst { return a.bst > b.bst }
            if a.captureRate != b.captureRate { return a.captureRate < b.captureRate }
            return a.id < b.id
        }.first
    }
    /// One 0.5% legendary gate, with the immediately preceding species excluded.
    /// If the area's only legend was just seen, this encounter uses the ordinary pool.
    func choose(in area: SafariArea, roll: Double, index: UInt64, excludingSpeciesID: Int? = nil) throws -> SafariSpecies {
        let entries = species.filter { $0.area == area && $0.id != excludingSpeciesID }
        let legends = entries.filter(\.legendary)
        let pool = !legends.isEmpty && roll < 0.005 ? legends : entries.filter { !$0.legendary }
        guard !pool.isEmpty else { throw SafariError.catalog }
        return pool[Int(index % UInt64(pool.count))]
    }
}

enum SafariError: Error { case catalog, invalidAction, noTicket, invalidSave }
enum SafariAction: String, CaseIterable, Sendable { case ball, rock, bait, run }
enum SafariPhase: String, Codable, Sendable { case encounter, replacement, between, finished }
enum SafariNotice: String, Codable, Sendable { case appeared, missed, caught, fled, waited, ran, rock, bait, ended, replaced, kept }

struct SafariPokemon: Codable, Sendable, Equatable, Identifiable {
    var id: String { profile.instanceID }
    let species: SafariSpecies
    var profile: PokemonProfile
    let nature: PokemonNature
    let shiny: Bool
}

/// Pure value state. The store commits a complete next value before publishing any result.
struct SafariSession: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let startedAt: Date
    var randomState: UInt64
    var area: SafariArea
    var visited: [SafariArea]
    var ballsRemaining = 20
    var areaBalls = 0
    var encounters = 0
    var turn = 0
    var catchModifier = 0.0
    var fleeModifier = 0.0
    var wild: SafariPokemon?
    var carried: SafariPokemon?
    var pendingCatch: SafariPokemon?
    var pendingArea: SafariArea? = nil
    var phase: SafariPhase = .between
    var notices: [SafariNotice] = []
    var registeredSpeciesCount: Int? = nil
    var lastCapture: SafariCaptureResult? = nil
    var claimed = false
    var shinyDenominator: UInt64
    /// A deliberate player escape pauses exploration, including after an app restart.
    var shouldAdvanceAutomatically: Bool { phase == .between && pendingArea == nil && !notices.contains(.ran) }
    var areaBallLimit: Int { visited.count == 3 ? 8 : 6 }
    var captureOdds: SafariCaptureOdds {
        SafariCaptureOdds(captureRate:wild?.species.captureRate ?? 0,shiny:wild?.shiny ?? false,
                          registeredSpecies:registeredSpeciesCount ?? 0,modifier:catchModifier)
    }
    var catchChance: Double { captureOdds.successProbability*100 }
    var fleeChance: Double { Self.clamp((wild?.species.fleeChance ?? 0) + fleeModifier) }
    private static func clamp(_ value: Double) -> Double { min(100, max(0, value)) }

    init(area: SafariArea, seed: UInt64, shinyDenominator: UInt64, now: Date = Date(), id: String = UUID().uuidString) {
        self.id = id; startedAt = now; randomState = seed; self.area = area; visited = [area]
        self.shinyDenominator = max(1, shinyDenominator)
    }
    private mutating func next() -> UInt64 {
        // Same saved stream for species, individual values and outcomes. Never reroll on UI redraw.
        randomState &+= 0x9E3779B97F4A7C15
        var value = randomState
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
    private mutating func roll() -> Double { Double(next() >> 11) / 9_007_199_254_740_992 }

    mutating func continueJourney(catalog: SafariCatalog) throws {
        guard phase == .between, pendingArea == nil else { throw SafariError.invalidAction }
        if ballsRemaining == 0 { finish(); return }
        if areaBalls >= areaBallLimit || encounters >= 5 {
            guard visited.count < 3 else { finish(); return }
            let choices = SafariArea.allCases.filter { !visited.contains($0) }
            // Persist the destination before presenting it. Confirmation alone moves
            // the camera and creates the next encounter; retries cannot reroll it.
            pendingArea = choices[Int(next() % UInt64(choices.count))]
            return
        }
        let gate = roll(), index = next()
        // wild retains the last encounter across Run/catch, area confirmation and
        // save reloads. Exclude that species, rather than the Pokémon being carried.
        let species = try catalog.choose(in: area, roll: gate, index: index, excludingSpeciesID:wild?.species.id)
        let seed = next()
        // Use the application's completed-growth convention for final-form Safari catches.
        var profile = PokemonProfile.generate(seed: seed)
        profile.advanceGrowth(to: PokemonBalance.graduationTotal(species.rarity), rarity: species.rarity)
        let nature = PokemonNature.allCases[Int(next() % UInt64(PokemonNature.allCases.count))]
        let shiny = next() % shinyDenominator == 0
        wild = SafariPokemon(species: species, profile: profile, nature: nature, shiny: shiny)
        turn = 0; catchModifier = 0; fleeModifier = 0; lastCapture = nil; encounters += 1
        notices = [.appeared]; phase = .encounter
    }

    mutating func confirmAreaChange(catalog: SafariCatalog) throws {
        guard phase == .between, let destination = pendingArea else { throw SafariError.invalidAction }
        area = destination; visited.append(destination); pendingArea = nil
        areaBalls = 0; encounters = 0
        try continueJourney(catalog:catalog)
    }

    mutating func act(_ action: SafariAction) throws {
        guard phase == .encounter, let wild else { throw SafariError.invalidAction }
        notices = []; lastCapture = nil
        if action == .run { notices = [.ran]; endEncounter(); return }
        turn += 1
        switch action {
        case .ball:
            guard ballsRemaining > 0, areaBalls < areaBallLimit else { throw SafariError.invalidAction }
            ballsRemaining -= 1; areaBalls += 1
            let odds = captureOdds
            var result = odds.resolve(next: { next() })
            result.visualSeed = randomState
            lastCapture = result
            if result.caught {
                notices = [.caught]
                if carried == nil { carried = wild; endEncounter() }
                else { pendingCatch = wild; endEncounter(phase: .replacement) }
                return
            }
            notices = [.missed]
        case .rock: catchModifier += 5; notices = [.rock]
        case .bait: catchModifier -= 3; fleeModifier -= 5; notices = [.bait]
        case .run: break
        }
        // Exactly one wild response; turn five overrides any bait protection.
        let chance = action == .rock ? 40 : fleeChance
        if turn >= 5 || roll() * 100 < chance { notices.append(.fled); endEncounter() }
        else { notices.append(.waited) }
        if ballsRemaining == 0 || areaBalls >= areaBallLimit { endEncounter() }
    }
    private mutating func endEncounter(phase: SafariPhase = .between) {
        self.phase = phase; catchModifier = 0; fleeModifier = 0
    }
    mutating func resolveCatch(replace: Bool) throws {
        guard phase == .replacement, let pendingCatch else { throw SafariError.invalidAction }
        if replace { carried = pendingCatch }
        self.pendingCatch = nil; phase = .between; notices = [replace ? .replaced : .kept]
    }
    mutating func finish() {
        phase = .finished; wild = nil; pendingCatch = nil; pendingArea = nil
        catchModifier = 0; fleeModifier = 0; notices = [.ended]
    }
    /// External saves may not bypass limits or inject a species outside the fixed catalog.
    func validate(catalog: SafariCatalog) throws {
        guard !id.isEmpty, (1...3).contains(visited.count), Set(visited).count == visited.count,
              visited.last == area, (0...20).contains(ballsRemaining),
              (0...areaBallLimit).contains(areaBalls), (0...5).contains(encounters), (0...5).contains(turn),
              catchModifier.isFinite, fleeModifier.isFinite,
              (-15...25).contains(catchModifier), (-25...0).contains(fleeModifier),
              shinyDenominator > 0, (registeredSpeciesCount ?? 0) >= 0, lastCapture?.isValid != false,
              phase != .replacement || pendingCatch != nil,
              pendingArea.map({ destination in phase == .between && visited.count < 3 && ballsRemaining > 0 &&
                  !visited.contains(destination) && (areaBalls >= areaBallLimit || encounters >= 5) }) ?? true,
              phase != .encounter || (wild != nil && turn < 5 && ballsRemaining > 0 && areaBalls < areaBallLimit),
              [wild, carried, pendingCatch].compactMap({ $0 }).allSatisfy({ pokemon in
                  catalog.species.contains(pokemon.species) && pokemon.profile.level == 100
              }) else { throw SafariError.invalidSave }
    }
}
