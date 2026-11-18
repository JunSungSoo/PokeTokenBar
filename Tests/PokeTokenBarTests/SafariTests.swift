import AppKit
import SwiftUI
import XCTest
import Vision
@testable import PokeTokenBar

private struct SafariNoProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

final class SafariEngineTests: XCTestCase {
    private func catalog() throws -> SafariCatalog { try SafariCatalog.load() }
    private func session(area: SafariArea = .plains, seed: UInt64 = 1) throws -> SafariSession {
        var session = SafariSession(area: area, seed: seed, shinyDenominator: 4096)
        try session.continueJourney(catalog: catalog())
        return session
    }
    func testFixedCatalogAndAllDualTypes() throws {
        let catalog = try catalog(); try catalog.validate()
        XCTAssertEqual(catalog.species.count, 228)
        XCTAssertEqual(Set(catalog.species.map(\.id)).count, 228)
        XCTAssertEqual(catalog.species.filter { $0.area == .forest }.count, 46)
        XCTAssertTrue(catalog.species.filter { $0.area == .forest }.allSatisfy { $0.bst >= 400 })
        XCTAssertEqual(catalog.species.first { $0.id == 131 }?.area, .iceCave)
        XCTAssertEqual(catalog.species.first { $0.id == 637 }?.area, .volcano) // Bug/Fire
        XCTAssertEqual(catalog.species.first { $0.id == 389 }?.area, .desert) // Grass/Ground
        XCTAssertNotNil(catalog.species.first { $0.id == 25 })
        XCTAssertFalse(catalog.species.contains { [12,15,166,168,267,269,292,402].contains($0.id) })
    }
    func testAreaRepresentativesAreStableRareOrHighStatLocalSpecies() throws {
        let catalog = try catalog()
        let expected: [SafariArea:Int] = [.plains:486,.forest:251,.lake:245,.mountain:377,.desert:383,
            .volcano:250,.metropolis:145,.dojo:639,.cave:491,.fairyCave:249,.iceCave:144]
        for area in SafariArea.allCases {
            let representative = try XCTUnwrap(catalog.representative(in:area))
            XCTAssertEqual(representative.id,expected[area])
            XCTAssertEqual(representative.area,area)
            XCTAssertEqual(SafariCatalog(species:catalog.species.reversed()).representative(in:area),representative)
        }
    }
    func testPlayerEscapeWaitsForContinueWithoutAnyEncounterLimit() throws {
        let catalog = try catalog()
        var value = try session()
        for _ in 0..<12 { try value.act(.run); try value.continueJourney(catalog:catalog) }
        XCTAssertEqual(value.encounters,13)
        try value.act(.run)
        XCTAssertFalse(value.shouldAdvanceAutomatically)
        value = try JSONDecoder().decode(SafariSession.self,from:JSONEncoder().encode(value))
        XCTAssertEqual(value.area,.plains); XCTAssertNil(value.pendingAreaOptions)
        try value.continueJourney(catalog:catalog)
        XCTAssertEqual(value.encounters,14); XCTAssertEqual(value.visited.count,1)
    }

    func testCaptureUsesSpeciesRateAndFleeStillUsesBST() {
        func mon(_ bst:Int,legendary:Bool = false) -> SafariSpecies {
            SafariSpecies(id:25,area:.metropolis,types:["electric"],bst:bst,legendary:legendary,captureRate:45)
        }
        let expected = SafariCaptureOdds(captureRate:45).successProbability*100
        for bst in [300,399,400,499,500,549,550,580,599,600,680] {
            XCTAssertEqual(mon(bst).catchChance,expected)
            XCTAssertEqual(mon(bst).fleeChance,bst >= 600 ? 40:25)
        }
        XCTAssertEqual(mon(580,legendary:true).catchChance,expected)
    }
    func testEveryAreaHasTypeMatchedLegendaryOrMythicalWithThreePercentPerSpecies() throws {
        let catalog = try catalog()
        let expected:[SafariArea:Set<Int>] = [.plains:[486],.forest:[251],.lake:[245],.mountain:[377],.desert:[383],
            .volcano:[146,250],.metropolis:[145],.dojo:[639],.cave:[491],.fairyCave:[249],.iceCave:[144]]
        for area in SafariArea.allCases {
            let legends = catalog.species.filter { $0.area == area && $0.legendary }
            XCTAssertEqual(Set(legends.map(\.id)),expected[area])
            XCTAssertTrue(legends.allSatisfy { $0.rarity == .legendary })
            var legendCount = 0
            for i in 0..<10_000 {
                let chosen = try catalog.choose(in:area,roll:(Double(i)+0.5)/10_000,index:UInt64(i))
                if chosen.legendary { legendCount += 1; XCTAssertTrue(expected[area]!.contains(chosen.id)) }
            }
            XCTAssertEqual(legendCount,300*legends.count,"Each eligible species contributes its own 3%")
        }
    }
    func testCatalogRejectsARegionLeftWithoutALegendEvenWhenTypesAndCountsRemainValid() throws {
        let catalog = try catalog()
        // Terrakion matches Mountain's Rock type too, but moving it leaves Dojo's
        // fifteen ordinary species without a legend. Other IDs/types/counts stay valid.
        let relocated = catalog.species.map { mon in
            mon.id == 639 ? SafariSpecies(id:mon.id,area:.mountain,types:mon.types,bst:mon.bst,
                legendary:mon.legendary,captureRate:mon.captureRate):mon
        }
        XCTAssertEqual(relocated.filter { $0.area == .dojo }.count,15)
        XCTAssertThrowsError(try SafariCatalog(species:relocated).validate())
    }
    func testVolcanoLegendsEachHaveThreePercentAndCombinedSixPercent() throws {
        let catalog = try catalog()
        var counts: [Int:Int] = [:]
        for i in 0..<10_000 {
            let mon = try catalog.choose(in: .volcano, roll: (Double(i)+0.5)/10_000, index: UInt64(i))
            if mon.legendary { counts[mon.id, default:0] += 1 }
        }
        XCTAssertEqual(counts,[146:300,250:300])
        XCTAssertTrue(try catalog.choose(in:.forest,roll:0,index:0).legendary)
        XCTAssertFalse(try catalog.choose(in:.volcano,roll:0.06,index:0).legendary)
    }
    func testEveryAreaExcludesImmediatelyPreviousSpeciesFromBothEncounterPools() throws {
        let catalog = try catalog()
        for area in SafariArea.allCases {
            let entries = catalog.species.filter { $0.area == area }
            for previous in entries {
                for roll in [0.0,0.029999,0.03,0.059999,0.06,0.5] {
                    for index in 0..<entries.count {
                        let next = try catalog.choose(in:area,roll:roll,index:UInt64(index),excludingSpeciesID:previous.id)
                        XCTAssertNotEqual(next.id,previous.id)
                        XCTAssertEqual(next.area,area)
                    }
                }
            }
        }
    }
    func testLegendGateRetainedForEligibleLegendsAndSolePreviousLegendFallsBackToOrdinary() throws {
        let catalog = try catalog()
        for previous in [146,250] {
            var legends = 0
            for i in 0..<10_000 {
                let next = try catalog.choose(in:.volcano,roll:(Double(i)+0.5)/10_000,
                    index:UInt64(i),excludingSpeciesID:previous)
                XCTAssertNotEqual(next.id,previous)
                if next.legendary { legends += 1; XCTAssertEqual(next.id,previous == 146 ? 250:146) }
            }
            XCTAssertEqual(legends,300)
        }
        for (area,previous) in [(SafariArea.iceCave,144),(.metropolis,145),(.fairyCave,249)] {
            let next = try catalog.choose(in:area,roll:0,index:0,excludingSpeciesID:previous)
            XCTAssertFalse(next.legendary)
            XCTAssertNotEqual(next.id,previous)
        }
    }
    func testManySavedEncountersNeverRepeatSpeciesOrTriggerAreaTransferWithoutBalls() throws {
        let catalog = try catalog()
        for seed in 0..<128 {
            var value = SafariSession(area:.forest,seed:UInt64(seed),shinyDenominator:4096)
            try value.continueJourney(catalog:catalog)
            var previous:Int?
            for _ in 0..<40 {
                let current = try XCTUnwrap(value.wild?.species.id)
                XCTAssertNotEqual(current,previous); previous=current
                try value.act(.run)
                value = try JSONDecoder().decode(SafariSession.self,from:JSONEncoder().encode(value))
                try value.continueJourney(catalog:catalog)
                XCTAssertNil(value.pendingAreaOptions); XCTAssertEqual(value.area,.forest)
            }
            XCTAssertEqual(value.encounters,41); XCTAssertEqual(value.ballsRemaining,20)
        }
    }

    func testEncounterCounterDoesNotLimitExplorationAndCannotOverflow() throws {
        var value = try session()
        value.encounters = Int.max
        try value.act(.run); try value.continueJourney(catalog:catalog())
        XCTAssertEqual(value.phase,.encounter); XCTAssertEqual(value.encounters,Int.max)
        XCTAssertNil(value.pendingAreaOptions); XCTAssertEqual(value.visited.count,1)
        try value.validate(catalog:catalog())
    }

    func testBaitStacksInPercentagePointsAndResetsAtNewEncounter() throws {
        var value = try session()
        let baseCatch = value.catchChance
        // Common 25% flee reaches zero after three baits. Find a stream surviving four.
        var found: SafariSession?
        for seed in 0..<1000 {
            var candidate = value; candidate.randomState = UInt64(seed)
            for _ in 0..<4 { if candidate.phase == .encounter { try candidate.act(.bait) } }
            if candidate.phase == .encounter { found = candidate; break }
        }
        value = try XCTUnwrap(found)
        XCTAssertEqual(value.catchChance,max(0,baseCatch-20),accuracy:0.000001)
        XCTAssertEqual(value.fleeChance,0)
        try value.act(.bait)
        XCTAssertEqual(value.fleeModifier,0) // reset immediately when the encounter ends
        XCTAssertEqual(value.phase,.between) // forced turn-five flee overrides zero flee
        XCTAssertEqual(value.notices.last,.fled)
        try value.continueJourney(catalog:catalog())
        XCTAssertEqual(value.catchModifier,0); XCTAssertEqual(value.fleeModifier,0); XCTAssertEqual(value.turn,0)
    }
    func testRockCatchAndFleeBonusesStackInsteadOfUsingAFixedGate() throws {
        let sample = try session()
        var survivors = 0
        for seed in 0..<10_000 {
            var value = sample; value.randomState = UInt64(seed)
            try value.act(.rock)
            XCTAssertEqual(value.catchModifier,value.phase == .encounter ? 5 : 0)
            XCTAssertEqual(value.fleeModifier,value.phase == .encounter ? 10 : 0)
            XCTAssertEqual(value.notices.count,2)
            if value.phase == .encounter { survivors += 1 }
        }
        XCTAssertEqual(Double(survivors)/10_000,0.65,accuracy:0.02)
        var found = false
        for seed in 0..<1000 {
            var value = sample; value.randomState = UInt64(seed)
            try value.act(.rock)
            if value.phase == .encounter {
                try value.act(.rock)
                if value.phase == .encounter {
                    XCTAssertEqual(value.catchModifier,10); XCTAssertEqual(value.fleeModifier,20)
                    XCTAssertEqual(value.fleeChance,45); found = true; break
                }
            }
        }
        XCTAssertTrue(found)
    }
    func testRockAndBaitEffectsStackCancelPersistAndResetAsPercentagePoints() throws {
        let catalog = try catalog()
        let initial = try session(), baseCatch = try session().catchChance
        let sequences:[([SafariAction],Double,Double)] = [([.rock,.rock],10,20),([.bait,.bait],-10,-20),([.rock,.bait],0,0),([.bait,.rock],0,0)]
        for (actions,catchDelta,fleeDelta) in sequences {
            var survivor:SafariSession?
            for seed in 0..<1000 {
                var value = initial; value.randomState = UInt64(seed)
                for action in actions { if value.phase == .encounter { try value.act(action) } }
                if value.phase == .encounter { survivor = value; break }
            }
            var value = try XCTUnwrap(survivor)
            XCTAssertEqual(value.catchModifier,catchDelta)
            XCTAssertEqual(value.fleeModifier,fleeDelta)
            XCTAssertEqual(value.catchChance,min(100,max(0,baseCatch+catchDelta)),accuracy:1e-6)
            XCTAssertEqual(value.fleeChance,min(100,max(0,25+fleeDelta)))
            try value.validate(catalog:catalog)
            value = try JSONDecoder().decode(SafariSession.self,from:JSONEncoder().encode(value))
            var state = CompanionState(); state.safariSession = value
            XCTAssertEqual(SaveTransfer.sanitized(state).safariSession,value)
            try value.act(.run); try value.continueJourney(catalog:catalog)
            XCTAssertEqual(value.catchModifier,0); XCTAssertEqual(value.fleeModifier,0)
        }
    }
    func testBaitUsesOneReducedFleeGatePerTurn() throws {
        let initial = try session()
        var fled = 0
        for seed in 0..<10_000 {
            var value = initial; value.randomState = UInt64(seed)
            try value.act(.bait)
            XCTAssertEqual(value.notices.filter { $0 == .fled || $0 == .waited }.count,1)
            if value.notices.contains(.fled) { fled += 1 }
            else { XCTAssertEqual(value.fleeChance,15); XCTAssertEqual(value.fleeModifier,-10) }
        }
        XCTAssertEqual(Double(fled)/10_000,0.15,accuracy:0.02)
    }
    func testWildChoosesFleeOrWaitEachTurnWithoutWaitingForOneHundredPercent() throws {
        let catalog = try catalog()
        for (speciesID,expected) in [(20,0.25),(289,0.40)] {
            let species = try XCTUnwrap(catalog.species.first { $0.id == speciesID })
            var initial = try session()
            let original = try XCTUnwrap(initial.wild)
            initial.wild = SafariPokemon(species:species,profile:original.profile,nature:original.nature,shiny:false)
            var responses = [0,0], fled = [0,0], waited = [0,0]
            for seed in 0..<10_000 {
                var value = initial; value.randomState = UInt64(seed)
                for turn in 0..<2 {
                    guard value.phase == .encounter else { break }
                    try value.act(.ball)
                    if value.notices.contains(.caught) {
                        XCTAssertFalse(value.notices.contains(.fled)); XCTAssertFalse(value.notices.contains(.waited))
                        break
                    }
                    XCTAssertTrue(value.notices.contains(.missed))
                    XCTAssertEqual(value.notices.filter { $0 == .fled || $0 == .waited }.count,1)
                    XCTAssertEqual(value.turn,turn+1)
                    responses[turn] += 1
                    if value.notices.contains(.fled) { fled[turn] += 1 }
                    else { waited[turn] += 1 }
                }
            }
            for turn in 0..<2 {
                XCTAssertGreaterThan(fled[turn],0,"Flee is possible before turn five, below 100%")
                XCTAssertGreaterThan(waited[turn],0,"Waiting is also possible in the same turn")
                XCTAssertEqual(Double(fled[turn])/Double(responses[turn]),expected,accuracy:0.025,
                    "Each new turn uses the same independent base flee chance")
            }
        }
    }



    func testNatureAndAllSixIndividualValuesAreRolledAtEncounterAndNeverRerolledByActions() throws {
        let catalog = try catalog()
        var natures = Set<PokemonNature>(), individualValues = Array(repeating:Set<Int>(),count:6)
        for seed in 0..<512 {
            var value = SafariSession(area:.forest,seed:UInt64(seed),shinyDenominator:4096)
            try value.continueJourney(catalog:catalog)
            let observed = try XCTUnwrap(value.wild)
            XCTAssertEqual(observed.profile.level,100)
            XCTAssertEqual(observed.profile.growthTokens,PokemonBalance.graduationTotal(observed.species.rarity))
            natures.insert(observed.nature)
            for (index,stat) in PokemonStatCalculator.order.enumerated() {
                let iv = observed.profile.ivs[stat]
                XCTAssertTrue((0...31).contains(iv))
                XCTAssertTrue((1...32).contains(PokemonStatGrade.rank(iv:iv)))
                individualValues[index].insert(iv)
            }
            value = try JSONDecoder().decode(SafariSession.self,from:JSONEncoder().encode(value))
            XCTAssertEqual(value.wild,observed)
            try value.act(seed.isMultiple(of:2) ? .rock:.bait)
            XCTAssertEqual(value.wild,observed)
        }
        XCTAssertEqual(natures,Set(PokemonNature.allCases))
        for values in individualValues { XCTAssertEqual(values,Set(0...31)) }
    }

    func testLegacyAreaMigrationPreservesCatchAndDoesNotDiscardEntireTrip() throws {
        let catalog = try catalog()
        let original = try session()
        for thirdArea in [false,true] {
            var old = original; old.areaRulesVersion = nil; old.carried = old.wild
            old.phase = .between; old.encounters = 5; old.areaBalls = 6
            old.visited = thirdArea ? [.forest,.lake,.plains]:[.plains]
            old.pendingArea = thirdArea ? nil:.forest
            var state = CompanionState(); state.safariSession = old
            let migrated = try XCTUnwrap(SaveTransfer.sanitized(state).safariSession)
            XCTAssertEqual(migrated.carried,old.carried)
            XCTAssertEqual(migrated.areaRulesVersion,SafariSession.currentAreaRulesVersion)
            XCTAssertNil(migrated.pendingArea)
            // Free travel keeps every older trip going with its remaining balls.
            XCTAssertEqual(migrated.phase,.between)
            try migrated.validate(catalog:catalog)
            XCTAssertEqual(migrated.area,old.area); XCTAssertEqual(migrated.encounters,5)
            XCTAssertEqual(migrated.areaBalls,0); XCTAssertEqual(migrated.ballsRemaining,20)
        }
        var pendingThird = original; pendingThird.areaRulesVersion = nil
        pendingThird.visited = [.forest,.plains]; pendingThird.pendingArea = .lake
        pendingThird.phase = .between; pendingThird.encounters = 5; pendingThird.carried = pendingThird.wild
        var state = CompanionState(); state.safariSession = pendingThird
        let resumed = try XCTUnwrap(SaveTransfer.sanitized(state).safariSession)
        XCTAssertEqual(resumed.phase,.between); XCTAssertNil(resumed.pendingArea)
        XCTAssertEqual(resumed.carried,pendingThird.carried)
    }
    func testLegacyThirdAreaReplacementStillLetsPlayerChooseTheirCatch() throws {
        var value = try session(); value.areaRulesVersion = nil
        value.visited = [.forest,.lake,.plains]
        value.phase = .replacement; value.carried = value.wild; value.pendingCatch = value.wild
        value.pendingCatch?.profile.instanceID = "new-legacy-catch"
        let pending = value.pendingCatch
        var state = CompanionState(); state.safariSession = value
        var migrated = try XCTUnwrap(SaveTransfer.sanitized(state).safariSession)
        XCTAssertEqual(migrated.phase,.replacement); XCTAssertEqual(migrated.pendingCatch,pending)
        try migrated.resolveCatch(replace:true)
        XCTAssertEqual(migrated.carried,pending); XCTAssertEqual(migrated.phase,.between)
        try migrated.validate(catalog:catalog())
    }
    func testDisplayedFleeChanceReflectsBaitAndForcedFifthResponse() throws {
        var value = try session()
        XCTAssertEqual(value.displayedFleeChance,value.fleeChance)
        value.fleeModifier = -10
        XCTAssertEqual(value.displayedFleeChance,value.wild!.species.fleeChance-10)
        value.turn = 4
        XCTAssertEqual(value.displayedFleeChance,100)
    }
    func testCaptureOnTurnFivePrecedesForcedFleeAndReplacementBlocksActions() throws {
        var value = try session()
        value.turn = 4; value.catchModifier = 100
        let old = try XCTUnwrap(value.wild)
        value.carried = old
        try value.act(.ball)
        XCTAssertEqual(value.phase,.replacement)
        XCTAssertEqual(value.turn,5)
        XCTAssertEqual(value.ballsRemaining,19)
        XCTAssertFalse(value.notices.contains(.fled))
        XCTAssertThrowsError(try value.act(.ball))
        XCTAssertThrowsError(try value.continueJourney(catalog:catalog()))
        var kept = value
        try kept.resolveCatch(replace:false)
        XCTAssertEqual(kept.carried,old); XCTAssertNil(kept.pendingCatch)
        try value.resolveCatch(replace:true)
        XCTAssertEqual(value.carried?.id,old.id); XCTAssertNil(value.pendingCatch)
    }
    func testNewCatchReplacesOnlyWhenAcceptedAndSlotsRemainOne() throws {
        var value = try session()
        let old = try XCTUnwrap(value.wild)
        value.carried = old
        try value.act(.run); try value.continueJourney(catalog:catalog())
        let new = try XCTUnwrap(value.wild)
        XCTAssertNotEqual(old.id,new.id)
        value.catchModifier = 100
        try value.act(.ball)
        var keep = value
        try keep.resolveCatch(replace:false); XCTAssertEqual(keep.carried?.id,old.id)
        try value.resolveCatch(replace:true); XCTAssertEqual(value.carried?.id,new.id)
    }
    func testRoundTripPreservesRandomStreamAndOutstandingReplacement() throws {
        var value = try session()
        value.catchModifier = 25
        value.carried = value.wild
        for seed in 0..<100 {
            var attempt = value; attempt.randomState = UInt64(seed)
            try attempt.act(.ball)
            if attempt.phase == .replacement { value = attempt; break }
        }
        XCTAssertEqual(value.phase,.replacement)
        let copy = try JSONDecoder().decode(SafariSession.self,from:JSONEncoder().encode(value))
        XCTAssertEqual(copy,value)
        try copy.validate(catalog:catalog())
        var a = copy, b = value
        try a.resolveCatch(replace:true); try b.resolveCatch(replace:true)
        // The next action on the same saved individual must produce exactly the same outcome.
        a.phase = .encounter; b.phase = .encounter
        try a.act(.ball); try b.act(.ball)
        XCTAssertEqual(a,b)
    }
    func testCatalogAndSaveRejectInvalidData() throws {
        let catalog = try catalog()
        XCTAssertThrowsError(try SafariCatalog(species:Array(catalog.species.dropFirst())).validate())
        var value = try session(); value.visited += [.forest,.lake,.forest]
        XCTAssertThrowsError(try value.validate(catalog:catalog),"a visited area is recorded once")
        value = try session(); value.visited = [.forest]
        XCTAssertThrowsError(try value.validate(catalog:catalog),"the current area is always visited")
        value = try session(); value.pendingAreaOptions = [.lake,.cave,.dojo]
        XCTAssertThrowsError(try value.validate(catalog:catalog),"no candidate prompt survives migration")
        value = try session(); value.visited += [.forest,.lake,.cave]
        XCTAssertNoThrow(try value.validate(catalog:catalog),"more than two areas is normal now")
        value = try session(); value.catchModifier = .nan
        XCTAssertThrowsError(try value.validate(catalog:catalog))
    }
}

@MainActor
final class SafariStoreTests: XCTestCase {
    private var directory: URL!
    private var file: URL { directory.appendingPathComponent("state.json") }
    private var defaults: UserDefaults!
    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("safari-tests-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defaults = UserDefaults(suiteName:"safari-tests-"+UUID().uuidString)!
        var state = CompanionState(); state.usedSinceInstall = 2_000_000_000
        state.inventory[ItemKind.safariTicket.rawValue] = 2
        try JSONEncoder().encode(state).write(to:file)
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at:directory) }
    private func store() -> CompanionStore { CompanionStore(provider:SafariNoProvider(),fileURL:file,defaults:defaults) }
    func testTicketIsFixedPriceAtBothStorePricePathsAndActualCheckout() throws {
        let store = store(); store.setShopDifficulty(2)
        XCTAssertEqual(store.price(of:.safariTicket),250_000_000)
        XCTAssertEqual(store.price(of:ShopEntry.item(.safariTicket)),250_000_000)
        XCTAssertTrue(store.buy(.safariTicket))
        XCTAssertEqual(store.availableTokens,1_750_000_000)
        XCTAssertEqual(store.itemCount(.safariTicket),3)
        store.setShopDifficulty(0.1)
        XCTAssertEqual(store.price(of:.safariTicket),250_000_000)
    }
    func testStartConsumesOneTicketResumeDoesNotAndOldStateIsCompatible() throws {
        let catalog = try SafariCatalog.load(), store = store()
        XCTAssertNil(store.safariSession)
        try store.startSafari(area:.forest,catalog:catalog)
        let original = try XCTUnwrap(store.safariSession)
        XCTAssertEqual(store.itemCount(.safariTicket),1)
        try store.startSafari(area:.volcano,catalog:catalog)
        XCTAssertEqual(store.itemCount(.safariTicket),1)
        XCTAssertEqual(store.safariSession,original)
        let reopened = self.store()
        XCTAssertEqual(reopened.safariSession,original)
        XCTAssertEqual(reopened.availableTokens,2_000_000_000)
    }
    func testNoTicketOrInvalidCatalogNeverStartsOrConsumes() throws {
        let store = store()
        XCTAssertThrowsError(try store.startSafari(area:.forest,catalog:SafariCatalog(species:[])))
        XCTAssertEqual(store.itemCount(.safariTicket),2)
        var state = store.state; state.inventory = [:]
        try JSONEncoder().encode(state).write(to:file)
        let empty = self.store()
        XCTAssertThrowsError(try empty.startSafari(area:.forest,catalog:SafariCatalog.load()))
        XCTAssertNil(empty.safariSession)
    }
    func testFailedDiskWriteDoesNotConsumeTicketOrPublishSession() throws {
        let store = store()
        try FileManager.default.removeItem(at:file)
        try FileManager.default.createDirectory(at:file,withIntermediateDirectories:false)
        XCTAssertThrowsError(try store.startSafari(area:.forest,catalog:SafariCatalog.load()))
        XCTAssertNil(store.safariSession)
        XCTAssertEqual(store.itemCount(.safariTicket),2)
    }
    func testExitCreditsOnlyKeptPokemonOnceAndPreservesWalletAndExistingCollection() throws {
        let catalog = try SafariCatalog.load(), store = store()
        try store.startSafari(area:.forest,catalog:catalog)
        var state = store.state
        var session = try XCTUnwrap(state.safariSession)
        session.carried = session.wild
        let kept = try XCTUnwrap(session.carried)
        state.safariSession = session
        try JSONEncoder().encode(state).write(to:file)
        let reopened = self.store()
        try reopened.safariExit()
        XCTAssertEqual(reopened.state.dex.count,1)
        XCTAssertEqual(reopened.state.dex.first?.id,kept.id)
        XCTAssertEqual(reopened.state.dex.first?.profile?.level,100)
        XCTAssertEqual(reopened.availableTokens,2_000_000_000)
        try reopened.safariExit()
        XCTAssertEqual(reopened.state.dex.count,1)
        let again = self.store()
        XCTAssertEqual(again.state.dex.count,1)
        XCTAssertTrue(again.safariSession?.claimed == true)
        try again.dismissSafari()
        XCTAssertNil(again.safariSession)
        XCTAssertEqual(again.state.dex.count,1)
    }
    func testZeroCatchExitAndLastTicketStillAllowsResume() throws {
        let store = store(), catalog = try SafariCatalog.load()
        try store.startSafari(area:.plains,catalog:catalog)
        try store.safariExit(); try store.dismissSafari()
        try store.startSafari(area:.lake,catalog:catalog)
        XCTAssertEqual(store.itemCount(.safariTicket),0)
        XCTAssertTrue(store.canEnterSafari)
        try store.safariExit(); try store.dismissSafari()
        XCTAssertFalse(store.canEnterSafari)
        XCTAssertTrue(store.state.dex.isEmpty)
    }
    func testActualFinishButtonAwardsKeptPokemonAndDismissesWithoutShowingWindow() async throws {
        let store = store(), catalog = try SafariCatalog.load()
        store.setLanguage(.ko)
        try store.startSafari(area:.forest,catalog:catalog)
        var state = store.state
        let kept = try XCTUnwrap(state.safariSession?.wild)
        state.safariSession?.carried = kept
        try JSONEncoder().encode(state).write(to:file)
        let reopened = self.store()
        reopened.setLanguage(.ko)
        let host = NSHostingView(rootView:SafariView(store:reopened,playsMusic:false))
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:660,height:620),styleMask:.borderless,backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for:.milliseconds(100))
        host.layoutSubtreeIfNeeded()
        // Inspect actual rendered labels before clicking the production button.
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds))
        host.cacheDisplay(in:host.bounds,to:bitmap)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate; request.recognitionLanguages = ["ko-KR","en-US"]
        try VNImageRequestHandler(cgImage:XCTUnwrap(bitmap.cgImage)).perform([request])
        let text = request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator:" ") ?? ""
        for hidden in ["나가기","포획 판정"] { XCTAssertFalse(text.contains(hidden),text) }
        XCTAssertTrue(text.contains("종료"),text)
        XCTAssertTrue(text.contains("포획률"),text)
        XCTAssertTrue(text.contains("도주율"),text)
        XCTAssertTrue(text.contains("%"),text)
        XCTAssertTrue(text.contains("누적"),text)
        func buttons(_ view:NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons)
        }
        let finish = try XCTUnwrap(buttons(host).first { $0.accessibilityIdentifier() == "safari-finish" })
        XCTAssertTrue(finish.isEnabled)
        finish.performClick(nil)
        try await Task.sleep(for:.milliseconds(100))
        XCTAssertFalse(window.isVisible)
        XCTAssertNil(reopened.safariSession)
        XCTAssertEqual(reopened.state.dex.map(\.id),[kept.id])
        XCTAssertEqual(reopened.availableTokens,store.availableTokens)
        let saved = self.store()
        XCTAssertNil(saved.safariSession); XCTAssertEqual(saved.state.dex.map(\.id),[kept.id])
        XCTAssertThrowsError(try saved.finishAndDismissSafari())
        XCTAssertEqual(saved.state.dex.count,1)
    }
    func testRealCaptureKeepsEncounterNatureAndIVsInGraduatedLogAndOwnedIndividuals() throws {
        let catalog = try SafariCatalog.load(), store = store()
        try store.startSafari(area:.forest,catalog:catalog)
        var state = store.state, session = try XCTUnwrap(store.safariSession)
        let observed = try XCTUnwrap(session.wild)
        // Find an actual successful capture stream without changing capture odds or the individual.
        var seed:UInt64?
        for candidate in 0..<1000 {
            var attempt = session; attempt.randomState = UInt64(candidate)
            try attempt.act(.ball)
            if attempt.carried != nil { seed = UInt64(candidate); break }
        }
        session.randomState = try XCTUnwrap(seed)
        state.safariSession = session
        try JSONEncoder().encode(state).write(to:file)
        let capturing = self.store()
        XCTAssertEqual(capturing.safariSession?.wild,observed)
        try capturing.safariAct(.ball)
        XCTAssertEqual(capturing.safariSession?.carried,observed)
        let resumed = self.store()
        XCTAssertEqual(resumed.safariSession?.carried,observed)
        try resumed.finishAndDismissSafari()
        let owned = self.store(), entry = try XCTUnwrap(owned.dexEntriesSorted.first { $0.id == observed.id })
        XCTAssertFalse(entry.isReleased); XCTAssertFalse(owned.isActiveDexEntry(entry))
        XCTAssertNotNil(entry.caughtAt)
        XCTAssertEqual(entry.nature,observed.nature)
        let profile = try XCTUnwrap(entry.profile)
        XCTAssertEqual(profile.level,100)
        XCTAssertEqual(profile.growthTokens,PokemonBalance.graduationTotal(entry.rarity))
        XCTAssertEqual(profile.ivs,observed.profile.ivs)
        XCTAssertEqual(profile.seed,observed.profile.seed)
        XCTAssertEqual(profile.instanceID,observed.id)
        XCTAssertEqual(owned.pokemonIndividuals(speciesID:observed.species.id).map(\.id),[observed.id])
        XCTAssertTrue(owned.state.collectedFinals.contains("\(observed.species.id):\(observed.species.id)"))
        let base = Dictionary(uniqueKeysWithValues:PokemonStatCalculator.order.map { ($0,100) })
        XCTAssertEqual(PokemonStatCalculator.stats(baseStats:base,speciesID:observed.species.id,profile:profile,nature:entry.nature),
                       PokemonStatCalculator.stats(baseStats:base,speciesID:observed.species.id,profile:observed.profile,nature:observed.nature))
    }
    func testFinishWithoutCatchAndAlreadyAwardedFinishDoNotDuplicateRewards() throws {
        let store = store(), catalog = try SafariCatalog.load()
        try store.startSafari(area:.forest,catalog:catalog)
        try store.finishAndDismissSafari()
        XCTAssertNil(store.safariSession); XCTAssertTrue(store.state.dex.isEmpty)
        try store.startSafari(area:.forest,catalog:catalog)
        var state = store.state
        let kept = try XCTUnwrap(state.safariSession?.wild)
        state.safariSession?.carried = kept
        try JSONEncoder().encode(state).write(to:file)
        let reopened = self.store()
        try reopened.safariExit() // Automatic limit/old-version finished screen already credited.
        XCTAssertEqual(reopened.state.dex.map(\.id),[kept.id])
        try reopened.finishAndDismissSafari()
        XCTAssertNil(reopened.safariSession); XCTAssertEqual(reopened.state.dex.map(\.id),[kept.id])
    }
    func testFailedFinishSavePreservesSessionAndCatch() throws {
        let store = store(), catalog = try SafariCatalog.load()
        try store.startSafari(area:.forest,catalog:catalog)
        var state = store.state
        let kept = state.safariSession?.wild
        state.safariSession?.carried = kept
        try JSONEncoder().encode(state).write(to:file)
        let reopened = self.store(), before = reopened.state
        try FileManager.default.removeItem(at:file)
        try FileManager.default.createDirectory(at:file,withIntermediateDirectories:false)
        XCTAssertThrowsError(try reopened.finishAndDismissSafari())
        XCTAssertEqual(reopened.safariSession,before.safariSession)
        XCTAssertNotNil(reopened.safariSession?.carried)
        XCTAssertEqual(reopened.state.dex.count,before.dex.count)
    }
    func testBackSpriteAndEveryBackgroundExistWithoutOpeningWindows() throws {
        let image = try XCTUnwrap(SafariArtwork.redBack)
        XCTAssertEqual(image.size,NSSize(width:64,height:64))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data:try XCTUnwrap(image.tiffRepresentation)))
        XCTAssertEqual(bitmap.colorAt(x:0,y:0)?.alphaComponent,0)
        var opaque = 0
        for y in 0..<64 { for x in 0..<64 { if (bitmap.colorAt(x:x,y:y)?.alphaComponent ?? 0)>0 { opaque += 1 } } }
        XCTAssertGreaterThan(opaque,500)
        for area in SafariArea.allCases { XCTAssertNotNil(SafariArtwork.arena(area)) }
        XCTAssertNil(SafariWindowController.shared.window)
    }
    func testRedDisplayRepeatsOriginalPixelsExactlyWithoutBlur() throws {
        let original = try XCTUnwrap(SafariArtwork.redBack?.cgImage(forProposedRect:nil,context:nil,hints:nil))
        let enlarged = try XCTUnwrap(SafariArtwork.redDisplayPixels)
        XCTAssertEqual(enlarged.width,original.width*3)
        XCTAssertEqual(enlarged.height,original.height*3)
        let source = NSBitmapImageRep(cgImage:original), target = NSBitmapImageRep(cgImage:enlarged)
        for y in 0..<64 { for x in 0..<64 {
            let color = try XCTUnwrap(source.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB))
            for dy in 0..<3 { for dx in 0..<3 {
                let pixel = try XCTUnwrap(target.colorAt(x:x*3+dx,y:y*3+dy)?.usingColorSpace(.deviceRGB))
                XCTAssertEqual(pixel.alphaComponent,color.alphaComponent,accuracy:0.005)
                if color.alphaComponent > 0 {
                    XCTAssertEqual(pixel.redComponent,color.redComponent,accuracy:0.005)
                    XCTAssertEqual(pixel.greenComponent,color.greenComponent,accuracy:0.005)
                    XCTAssertEqual(pixel.blueComponent,color.blueComponent,accuracy:0.005)
                }
            }}
        }}
    }
    /// Exercise the live view timer with music disabled, not a mocked engine-only escape.
    func testLiveViewNeverAdvancesAfterPlayerEscape() async throws {
        let store = store(), catalog = try SafariCatalog.load()
        try store.startSafari(area:.forest,catalog:catalog)
        try store.safariAct(.run)
        let before = store.safariSession
        let host = NSHostingView(rootView:SafariView(store:store,playsMusic:false))
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:660,height:620),styleMask:.borderless,backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds))
        host.cacheDisplay(in:host.bounds,to:bitmap)
        try await Task.sleep(for:.milliseconds(1550))
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(store.safariSession,before)
        try store.safariContinue(catalog:catalog)
        XCTAssertNotEqual(store.safariSession?.wild?.id,before?.wild?.id)
    }
    /// The auto-advance swaps the Next button for the action row under the cursor; Next overlaps Rock and Bait.
    func testActionsIgnoreClicksBrieflyAfterANewWildPokemonAppears() {
        let appeared = Date(timeIntervalSince1970: 1_000)
        var inputGuard = SafariInputGuard()
        XCTAssertTrue(inputGuard.accepts(at: appeared), "nothing is locked before an encounter appears")
        inputGuard.lock(at: appeared)
        XCTAssertFalse(inputGuard.accepts(at: appeared))
        XCTAssertFalse(inputGuard.accepts(at: appeared.addingTimeInterval(0.4)), "a click meant for Next is ignored")
        XCTAssertTrue(inputGuard.accepts(at: appeared.addingTimeInterval(SafariInputGuard.duration)))
        inputGuard.lock(at: appeared.addingTimeInterval(10))
        XCTAssertFalse(inputGuard.accepts(at: appeared.addingTimeInterval(10.2)), "every new encounter locks again")
    }
    /// Reproduces the report: a click aimed at Next lands after the auto-advance, on the Rock button.
    func testClickAtNextAfterAutoAdvanceDoesNotThrowARock() async throws {
        let store = store(), catalog = try SafariCatalog.load()
        try store.startSafari(area:.forest,catalog:catalog)
        for _ in 0..<5 { if store.safariSession?.phase == .encounter { try store.safariAct(.bait) } }
        XCTAssertEqual(store.safariSession?.phase,.between)
        let host = NSHostingView(rootView:SafariView(store:store,playsMusic:false))
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:660,height:620),styleMask:.borderless,backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.contentView = nil; window.close() }
        window.orderFrontRegardless(); host.layoutSubtreeIfNeeded()
        func click() {
            // Left half of Next, which becomes the right part of Rock after the swap.
            let point = NSPoint(x:310,y:167)
            for type in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
                window.sendEvent(NSEvent.mouseEvent(with:type,location:point,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,
                    windowNumber:window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!)
            }
        }
        try await Task.sleep(for:.milliseconds(1400))
        XCTAssertEqual(store.safariSession?.phase,.encounter,"the timer brought the next wild Pokémon")
        let appeared = store.safariSession
        click()
        try await Task.sleep(for:.milliseconds(50))
        XCTAssertEqual(store.safariSession,appeared,"the stray click is ignored")
        try await Task.sleep(for:.milliseconds(600))
        click()
        try await Task.sleep(for:.milliseconds(50))
        XCTAssertEqual(store.safariSession?.notices.first,.rock,"a deliberate click after the pause still throws")
    }
    func testTravelButtonOpensAllOtherAreasAndMovesOnlyOnConfirm() async throws {
        let store = store(), catalog = try SafariCatalog.load()
        try store.startSafari(area:.forest,catalog:catalog)
        let host = NSHostingView(rootView:SafariView(store:store,playsMusic:false))
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:660,height:620),styleMask:.borderless,backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.contentView = nil; window.close() }
        func buttons(_ view:NSView) -> [NSButton] { (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons) }
        func button(_ id:String) -> NSButton? { host.layoutSubtreeIfNeeded(); return buttons(host).first { $0.accessibilityIdentifier() == id } }
        func settle() async throws { try await Task.sleep(for:.milliseconds(100)); host.layoutSubtreeIfNeeded() }

        let travel = try XCTUnwrap(button("safari-travel"))
        XCTAssertTrue(travel.isEnabled,"travel is available during an encounter")
        travel.performClick(nil); try await settle()
        let options = buttons(host).compactMap { $0.accessibilityIdentifier() }.filter { $0.hasPrefix("safari-travel-option-") }
        XCTAssertEqual(Set(options),Set(SafariArea.allCases.filter { $0 != .forest }.map { "safari-travel-option-" + $0.rawValue }))
        XCTAssertFalse(try XCTUnwrap(button("safari-travel-confirm")).isEnabled,"nothing is chosen yet")

        try XCTUnwrap(button("safari-travel-cancel")).performClick(nil); try await settle()
        XCTAssertNil(button("safari-travel-confirm"),"cancel closes the picker")
        XCTAssertEqual(store.safariSession?.area,.forest)

        try XCTUnwrap(button("safari-travel")).performClick(nil); try await settle()
        try XCTUnwrap(button("safari-travel-option-lake")).performClick(nil); try await settle()
        try XCTUnwrap(button("safari-travel-confirm")).performClick(nil); try await settle()
        XCTAssertEqual(store.safariSession?.area,.lake)
        XCTAssertEqual(store.safariSession?.phase,.encounter)
        XCTAssertEqual(self.store().safariSession?.area,.lake,"the move is saved")

        var state = store.state
        var session = try XCTUnwrap(state.safariSession)
        session.carried = session.wild; session.pendingCatch = session.wild; session.phase = .replacement
        state.safariSession = session
        try JSONEncoder().encode(state).write(to:file)
        let replacing = self.store()
        let other = NSHostingView(rootView:SafariView(store:replacing,playsMusic:false))
        window.contentView = other; other.layoutSubtreeIfNeeded()
        try await Task.sleep(for:.milliseconds(100)); other.layoutSubtreeIfNeeded()
        XCTAssertFalse(try XCTUnwrap(buttons(other).first { $0.accessibilityIdentifier() == "safari-travel" }).isEnabled,
                       "the replacement choice cannot be skipped by travelling")
        XCTAssertFalse(try XCTUnwrap(buttons(other).first { $0.accessibilityIdentifier() == "safari-finish" }).isEnabled,
                       "Finish is also unavailable until the catch is chosen")
    }
    func testOpenPickerHoldsAutoAdvanceAndCancelResumesIt() async throws {
        let store = store(), catalog = try SafariCatalog.load()
        try store.startSafari(area:.forest,catalog:catalog)
        for _ in 0..<5 { if store.safariSession?.phase == .encounter { try store.safariAct(.bait) } }
        XCTAssertEqual(store.safariSession?.shouldAdvanceAutomatically,true)
        let host = NSHostingView(rootView:SafariView(store:store,playsMusic:false))
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:660,height:620),styleMask:.borderless,backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.contentView = nil; window.close() }
        func buttons(_ view:NSView) -> [NSButton] { (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons) }
        func button(_ id:String) -> NSButton? { host.layoutSubtreeIfNeeded(); return buttons(host).first { $0.accessibilityIdentifier() == id } }
        try XCTUnwrap(button("safari-travel")).performClick(nil)
        try await Task.sleep(for:.milliseconds(1600))
        XCTAssertEqual(store.safariSession?.phase,.between,"the timer waits while the picker is open")
        try XCTUnwrap(button("safari-travel-cancel")).performClick(nil)
        try await Task.sleep(for:.milliseconds(1600))
        XCTAssertEqual(store.safariSession?.phase,.encounter,"cancelling resumes the automatic advance")
        XCTAssertEqual(store.safariSession?.area,.forest)
    }
    func testLiveViewTimerStillAdvancesAfterWildFlees() async throws {
        let store = store(), catalog = try SafariCatalog.load()
        try store.startSafari(area:.forest,catalog:catalog)
        for _ in 0..<5 { if store.safariSession?.phase == .encounter { try store.safariAct(.bait) } }
        XCTAssertEqual(store.safariSession?.phase,.between)
        XCTAssertTrue(store.safariSession?.shouldAdvanceAutomatically == true)
        let before = store.safariSession?.wild?.id
        let host = NSHostingView(rootView:SafariView(store:store,playsMusic:false))
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:660,height:620),styleMask:.borderless,backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds))
        host.cacheDisplay(in:host.bounds,to:bitmap)
        try await Task.sleep(for:.milliseconds(1550))
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(store.safariSession?.phase,.encounter)
        XCTAssertNotEqual(store.safariSession?.wild?.id,before)
    }
    func testProductionViewRendersWithoutWindowOrAudio() throws {
        let store = store()
        try store.startSafari(area:.forest,catalog:SafariCatalog.load())
        let host = NSHostingView(rootView: SafariView(store:store,playsMusic:false).environment(\.colorScheme,.light))
        host.frame = NSRect(x:0,y:0,width:660,height:620)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds))
        host.cacheDisplay(in:host.bounds,to:bitmap)
        XCTAssertEqual(host.bounds.size,NSSize(width:660,height:620))
        XCTAssertGreaterThanOrEqual(bitmap.pixelsWide,660)
        XCTAssertEqual(Double(bitmap.pixelsWide)/Double(bitmap.pixelsHigh),660.0/620.0,accuracy:0.001)
        try bitmap.representation(using:.png,properties:[:])?.write(to:FileManager.default.temporaryDirectory.appendingPathComponent("ptb-safari-screen.png"))
        XCTAssertNil(SafariWindowController.shared.window)
    }
    func testLoadingLegacyThirdAreaKeepsCatchAndAwardsGraduateWithoutChangingWallet() throws {
        let store = store(), catalog = try SafariCatalog.load()
        try store.startSafari(area:.plains,catalog:catalog)
        var state = store.state
        let caught = try XCTUnwrap(state.safariSession?.wild)
        state.safariSession?.areaRulesVersion = nil
        state.safariSession?.visited = [.forest,.lake,.plains]
        state.safariSession?.carried = caught
        try JSONEncoder().encode(state).write(to:file)
        let loaded = self.store()
        XCTAssertEqual(loaded.safariSession?.phase,.encounter,"free travel keeps an older three-area trip going")
        XCTAssertEqual(loaded.safariSession?.carried,caught)
        XCTAssertEqual(loaded.availableTokens,store.availableTokens)
        try loaded.finishAndDismissSafari()
        XCTAssertNil(loaded.safariSession)
        XCTAssertEqual(loaded.state.dex.map(\.id),[caught.id])
        XCTAssertEqual(loaded.state.dex.first?.profile?.ivs,caught.profile.ivs)
        XCTAssertEqual(loaded.availableTokens,store.availableTokens)
        XCTAssertEqual(loaded.state.inventory,state.inventory)
        let saved = self.store()
        XCTAssertNil(saved.safariSession); XCTAssertEqual(saved.state.dex.map(\.id),[caught.id])
    }
    func testInvalidImportedSessionIsRemovedWithoutLosingCollectionOrBalance() throws {
        let store = store()
        try store.startSafari(area:.forest,catalog:SafariCatalog.load())
        var state = store.state
        state.safariSession?.turn = Int.max
        state.challengeCashClaims = ["existing-run":10_000_000]
        let clean = SaveTransfer.sanitized(state)
        XCTAssertNil(clean.safariSession)
        XCTAssertEqual(clean.usedSinceInstall,state.usedSinceInstall)
        XCTAssertEqual(clean.challengeCashClaims,state.challengeCashClaims)
        XCTAssertEqual(clean.inventory,state.inventory)
    }

    func testFinalBallCatchWaitsForReplacementAndAwardsOnlyChosenIndividual() throws {
        let catalog = try SafariCatalog.load(), store = store()
        try store.startSafari(area:.plains,catalog:catalog)
        var state = store.state
        var session = try XCTUnwrap(state.safariSession)
        let original = try XCTUnwrap(session.wild)
        session.carried = original
        try session.act(.run); try session.continueJourney(catalog:catalog)
        let new = try XCTUnwrap(session.wild)
        session.visited = [.lake,.plains]
        session.areaBalls = 9; session.ballsRemaining = 1
        // Find a naturally successful final ball, without altering the catch probability.
        var found = false
        for seed in 0..<1000 {
            var candidate = session; candidate.randomState = UInt64(seed)
            try candidate.act(.ball)
            if candidate.phase == .replacement { session.randomState = UInt64(seed); found = true; break }
        }
        XCTAssertTrue(found)
        state.safariSession = session
        try JSONEncoder().encode(state).write(to:file)
        let reopened = self.store()
        try reopened.safariAct(.ball)
        XCTAssertEqual(reopened.safariSession?.ballsRemaining,0)
        XCTAssertEqual(reopened.safariSession?.phase,.replacement)
        XCTAssertThrowsError(try reopened.safariExit())
        XCTAssertThrowsError(try reopened.finishAndDismissSafari())
        XCTAssertTrue(reopened.state.dex.isEmpty)
        let pending = self.store()
        XCTAssertEqual(pending.safariSession?.pendingCatch?.id,new.id)
        try pending.safariResolveCatch(replace:true)
        try pending.safariContinue(catalog:catalog)
        XCTAssertEqual(pending.safariSession?.phase,.finished)
        XCTAssertEqual(pending.state.dex.map(\.id),[new.id])
        XCTAssertFalse(pending.state.dex.contains { $0.id == original.id })
    }
    func testExportShopImageWhenRequested() throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_SAFARI_SHOP_IMAGE"] else {
            throw XCTSkip("Set PTB_SAFARI_SHOP_IMAGE to render the real Shop UI without a window")
        }
        let store = store()
        store.setLanguage(.ko)
        let host = NSHostingView(rootView: ShopView(store:store,nav:PopoverNavigation())
            .frame(width:PopoverMetrics.contentWidth,height:520).padding(14)
            .background(Color.white).environment(\.colorScheme,.light))
        host.frame = NSRect(x:0,y:0,width:PopoverMetrics.contentWidth+28,height:548)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds))
        host.cacheDisplay(in:host.bounds,to:bitmap)
        try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:output))
        XCTAssertNil(SafariWindowController.shared.window)
    }
    func testAllLanguagesHaveSafariText() {
        for language in AppLanguage.allCases {
            let l = L(language)
            XCTAssertFalse(l.safariTitle.isEmpty)
            for text in [l.safariCatchRate,l.safariFleeRate,l.safariRockHint,l.safariBaitHint] { XCTAssertFalse(text.isEmpty) }
            XCTAssertFalse(l.itemDescription(.safariTicket).isEmpty)
            for area in SafariArea.allCases { XCTAssertFalse(l.safariArea(area).isEmpty) }
            XCTAssertTrue(l.safariReplacement(old:"OLD",new:"NEW").contains("OLD"))
            XCTAssertTrue(l.safariReplacement(old:"OLD",new:"NEW").contains("NEW"))
        }
    }
}

final class SafariTravelTests: XCTestCase {
    private func catalog() throws -> SafariCatalog { try SafariCatalog.load() }
    private func session(area: SafariArea = .plains, seed: UInt64 = 1) throws -> SafariSession {
        var session = SafariSession(area: area, seed: seed, shinyDenominator: 4096)
        try session.continueJourney(catalog: catalog())
        return session
    }

    func testTravelMovesAnytimeWithoutSpendingBalls() throws {
        let catalog = try catalog()
        var value = try session()
        try value.act(.rock)
        let fleeing = try XCTUnwrap(value.wild?.id)
        if value.phase == .between { try value.continueJourney(catalog: catalog) }
        let ballsBefore = value.ballsRemaining
        value.catchModifier = 5; value.fleeModifier = 10; value.turn = 2
        XCTAssertEqual(value.travelDestinations.count, SafariArea.allCases.count - 1)
        XCTAssertFalse(value.travelDestinations.contains(.plains))

        try value.travel(to: .lake, catalog: catalog)
        XCTAssertEqual(value.area, .lake)
        XCTAssertEqual(value.phase, .encounter, "the first Pokémon of the new area appears at once")
        XCTAssertNotEqual(value.wild?.id, fleeing)
        XCTAssertEqual(value.wild?.species.area, .lake)
        XCTAssertEqual(value.ballsRemaining, ballsBefore)
        XCTAssertEqual(value.encounters, 1)
        XCTAssertEqual(value.turn, 0)
        XCTAssertEqual(value.catchModifier, 0)
        XCTAssertEqual(value.notices, [.appeared])
        try value.validate(catalog: catalog)

        try value.act(.run)
        try value.travel(to: .volcano, catalog: catalog)
        XCTAssertEqual(value.phase, .encounter, "travel also works between encounters")
        XCTAssertEqual(value.wild?.species.area, .volcano)
    }

    func testTravelRejectsCurrentAreaReplacementAndFinished() throws {
        let catalog = try catalog()
        var value = try session()
        let wild = value.wild
        XCTAssertThrowsError(try value.travel(to: .plains, catalog: catalog), "no free reroll in place")
        XCTAssertEqual(value.wild, wild)

        var replacing = value
        replacing.carried = value.wild; replacing.pendingCatch = value.wild; replacing.phase = .replacement
        XCTAssertThrowsError(try replacing.travel(to: .lake, catalog: catalog))

        var finished = value; finished.finish()
        XCTAssertThrowsError(try finished.travel(to: .lake, catalog: catalog))
    }

    func testRevisitIsAllowedAndVisitedStaysUnique() throws {
        let catalog = try catalog()
        var value = try session()
        for area in [SafariArea.lake, .cave, .plains, .lake, .iceCave, .forest, .desert, .dojo, .mountain, .volcano, .metropolis, .fairyCave] {
            try value.travel(to: area, catalog: catalog)
            try value.validate(catalog: catalog)
        }
        XCTAssertEqual(value.area, .fairyCave)
        XCTAssertEqual(Set(value.visited), Set(SafariArea.allCases))
        XCTAssertEqual(value.visited.count, SafariArea.allCases.count)
        let decoded = try JSONDecoder().decode(SafariSession.self, from: JSONEncoder().encode(value))
        try decoded.validate(catalog: catalog)
    }

    func testTwentyBallsStillFinishWithoutAreaLimits() throws {
        let catalog = try catalog()
        var value = try session()
        var throws_ = 0
        while value.phase != .finished && throws_ < 40 {
            if value.phase == .replacement { try value.resolveCatch(replace: false) }
            if value.phase == .between { try value.continueJourney(catalog: catalog); continue }
            if value.phase == .encounter { try value.act(.ball); throws_ += 1 }
        }
        XCTAssertEqual(throws_, 20, "every ball is thrown in one area; no ten-ball stop")
        XCTAssertEqual(value.ballsRemaining, 0)
        XCTAssertEqual(value.phase, .finished)
        XCTAssertEqual(value.visited, [.plains])
        XCTAssertNil(value.pendingAreaOptions)
    }

    func testLastBallAfterTravelEndsTheTrip() throws {
        let catalog = try catalog()
        var value = try session()
        value.ballsRemaining = 1
        try value.travel(to: .lake, catalog: catalog)
        try value.act(.ball)
        if value.phase == .replacement { try value.resolveCatch(replace: true) }
        if value.phase == .between { try value.continueJourney(catalog: catalog) }
        XCTAssertEqual(value.phase, .finished)
        XCTAssertThrowsError(try value.travel(to: .cave, catalog: catalog))
    }

    func testVersionThreeSaveWaitingForCandidatesMigrates() throws {
        let catalog = try catalog()
        var legacy = try session()
        try legacy.act(.run)
        legacy.areaBalls = 10; legacy.ballsRemaining = 10
        legacy.pendingAreaOptions = [.lake, .cave, .dojo]
        legacy.areaRulesVersion = 3
        legacy.carried = legacy.wild
        var state = CompanionState(); state.safariSession = legacy
        var value = try XCTUnwrap(SaveTransfer.sanitized(state).safariSession, "the real load path keeps the trip")
        XCTAssertEqual(value.areaRulesVersion, SafariSession.currentAreaRulesVersion)
        XCTAssertNil(value.pendingAreaOptions)
        XCTAssertEqual(value.areaBalls, 0)
        XCTAssertEqual(value.ballsRemaining, 10)
        XCTAssertEqual(value.carried, legacy.carried, "the kept Pokémon survives")
        XCTAssertTrue(value.shouldAdvanceAutomatically == false, "a deliberate escape still pauses")
        try value.validate(catalog: catalog)
        try value.travel(to: .dojo, catalog: catalog)
        XCTAssertEqual(value.phase, .encounter)

        var future = legacy; future.areaRulesVersion = SafariSession.currentAreaRulesVersion + 1
        var futureState = CompanionState(); futureState.safariSession = future
        XCTAssertNil(SaveTransfer.sanitized(futureState).safariSession, "a save from a newer app is not rewritten as current")
    }
}
