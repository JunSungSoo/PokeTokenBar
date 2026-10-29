import XCTest
@testable import PokeTokenBar

private struct MapleProvider:PokeProviding,PokemonDetailProviding {
    static let species:[Int:(String,String)]=[6:("charizard","blaze"),9:("blastoise","torrent"),3:("venusaur","overgrow"),94:("gengar","levitate"),143:("snorlax","immunity"),181:("ampharos","static")]
    func line(baseSpeciesID:Int) async throws->EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws->[BaseSpecies] { [] }
    func baseSpecies(id:Int) async throws->BaseSpecies? { nil }
    func pokemonDetails(speciesID:Int) async throws->PokemonDetails {
        PokemonDetails(speciesID:speciesID,name:Self.species[speciesID]!.0,height:10,weight:100,baseExperience:100,
            genderRate:1,types:["normal"],baseStats:Dictionary(uniqueKeysWithValues:PokemonStatCalculator.order.map{($0,100)}),
            abilities:[.init(name:Self.species[speciesID]!.1,slot:1,isHidden:false)],
            moves:[.init(name:"tackle",learnMethods:[.init(method:"level-up",level:1)])])
    }
}

@MainActor final class RedMapleTests:XCTestCase {
    private func fixture(stock:Int=0,withGraduates:Bool=true) throws->(CompanionStore,URL,UserDefaults) {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("maple-tests-\(UUID())")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let file=folder.appendingPathComponent("state.json")
        let suite="MapleTests.\(UUID())",defaults=try XCTUnwrap(UserDefaults(suiteName:suite))
        addTeardownBlock {try? FileManager.default.removeItem(at:folder);defaults.removePersistentDomain(forName:suite)}
        var state=CompanionState();state.installBaselineSet=true;state.usedSinceInstall=10*Mint.price
        state.inventory[ItemKind.redMaple.rawValue]=stock
        state.dex=[6,9,3,94,143,181].enumerated().map { i,id in
            var profile=PokemonProfile.generate(seed:UInt64(i+1),instanceID:"instance-\(i)")
            profile.level=100;profile.gender = .male;profile.abilityName=MapleProvider.species[id]!.1;profile.abilitySlot=1
            profile.moves=[.init(name:"tackle",learnedAtLevel:1)];profile.hasCustomMoves=true
            return DexEntry(id:"owned-\(i)",baseID:id,finalID:id,chainOrder:[id],rarity:.common,
                caughtAt:Date(),isShiny:i==0,nature:.adamant,profile:profile)
        }
        var released=state.dex[0];released.id="released";released.releasedAt=Date();state.dex.append(released)
        if !withGraduates {state.dex=[released]}
        try JSONEncoder().encode(state).write(to:file)
        return (CompanionStore(provider:MapleProvider(),fileURL:file,rng:SeededRNG(seed:42),defaults:defaults),file,defaults)
    }
    func testPurchaseUseAndPersistencePreserveEverythingExceptSixIVs() async throws {
        let (store,file,defaults)=try fixture()
        XCTAssertEqual(ItemKind.redMaple.shopPrice,ItemKind.mint.shopPrice)
        XCTAssertEqual(ItemKind.redMaple.fallbackEmoji,"🍁")
        XCTAssertTrue(store.purchasableItems.contains(.redMaple))
        XCTAssertTrue(store.buy(.redMaple))
        XCTAssertEqual(store.itemCount(.redMaple),1)
        XCTAssertTrue(store.canUseRedMaple)
        XCTAssertEqual(store.state.spentTokens,Mint.price)
        XCTAssertEqual(store.redMapleTargets.count,6)
        let before=store.state.dex[0],others=Array(store.state.dex.dropFirst())
        let ids=store.redMapleTargets.map(\.id)
        let originalTeam=try await BattleTeamBuilder.build(ids:ids,entries:store.state.dex,mode:.singles,language:.ko,provider:MapleProvider())
        XCTAssertTrue(store.useRedMaple(entryID:before.id))
        let after=store.state.dex[0]
        XCTAssertEqual(store.itemCount(.redMaple),0)
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try Array(store.state.dex.dropFirst()).map{try encoder.encode($0)},try others.map{try encoder.encode($0)})
        var restored=try XCTUnwrap(after.profile);restored.ivs=try XCTUnwrap(before.profile).ivs
        XCTAssertEqual(restored,before.profile)
        XCTAssertEqual(after.nature,before.nature);XCTAssertEqual(after.isShiny,before.isShiny)
        let team=try await BattleTeamBuilder.build(ids:ids,entries:store.state.dex,mode:.singles,language:.ko,provider:MapleProvider())
        XCTAssertNotEqual(team[0].stats,originalTeam[0].stats)
        for (name,key) in BattleTeamBuilder.statNames {XCTAssertEqual(team[0].ivs[key],after.profile?.ivs[name])}
        let details=try await MapleProvider().pokemonDetails(speciesID:6)
        XCTAssertEqual(team[0].stats,Dictionary(uniqueKeysWithValues:PokemonStatCalculator.stats(details:details,profile:try XCTUnwrap(after.profile),nature:after.nature).map{(BattleTeamBuilder.statNames[$0.name]!,$0.value)}))
        let reload=CompanionStore(provider:MapleProvider(),fileURL:file,defaults:defaults)
        XCTAssertEqual(reload.state.dex[0].profile,after.profile)
        XCTAssertEqual(reload.itemCount(.redMaple),0)
        XCTAssertFalse(reload.useRedMaple(entryID:before.id))
    }
    func testInvalidTargetsNeverConsumeAndRerollsUseAllThirtyTwoValues() throws {
        let (store,_,_)=try fixture(stock:256)
        XCTAssertFalse(store.useRedMaple(entryID:"released"))
        XCTAssertFalse(store.useRedMaple(entryID:"missing"))
        XCTAssertEqual(store.itemCount(.redMaple),256)
        var rolls=Dictionary(uniqueKeysWithValues:PokemonStatCalculator.order.map{($0,Set<Int>())})
        for _ in 0..<256 {
            XCTAssertTrue(store.useRedMaple(entryID:"owned-0"))
            let ivs=try XCTUnwrap(store.state.dex[0].profile).ivs
            for stat in PokemonStatCalculator.order { rolls[stat]!.insert(ivs[stat]);XCTAssertTrue((0...31).contains(ivs[stat])) }
        }
        for stat in PokemonStatCalculator.order {XCTAssertEqual(rolls[stat],Set(0...31),stat)}
        XCTAssertFalse(store.canUseRedMaple)
        for language in AppLanguage.allCases {
            XCTAssertFalse(L(language).itemName(.redMaple).isEmpty)
            XCTAssertFalse(L(language).itemDescription(.redMaple).isEmpty)
        }
        XCTAssertEqual(L(.ko).itemDescription(.redMaple),"선택한 포켓몬의 종족값을 랜덤하게 변경해요.")
    }
    func testStockWithoutAnyOwnedGraduateCannotBeUsed() throws {
        let (store,_,_)=try fixture(stock:2,withGraduates:false)
        XCTAssertTrue(store.redMapleTargets.isEmpty)
        XCTAssertFalse(store.canUseRedMaple)
        XCTAssertFalse(store.useRedMaple(entryID:"released"))
        XCTAssertEqual(store.itemCount(.redMaple),2)
    }
}
