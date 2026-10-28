import XCTest
@testable import PokeTokenBar

private struct FairyDetailProvider:PokemonDetailProviding {
    func pokemonDetails(speciesID:Int) async throws->PokemonDetails {PokemonFairyMoveTests.details(speciesID)}
}
@MainActor final class PokemonFairyMoveTests:XCTestCase {
    nonisolated static func details(_ id:Int)->PokemonDetails {
        let names=[282:"gardevoir",94:"gengar",26:"raichu",579:"reuniclus",547:"whimsicott",235:"smeargle",6:"charizard"]
        let abilities=[282:"synchronize",94:"levitate",26:"static",579:"overcoat",547:"prankster",235:"own-tempo",6:"blaze"]
        return PokemonDetails(speciesID:id,name:names[id] ?? "pikachu",height:16,weight:500,baseExperience:200,genderRate:4,
            types:["psychic"],baseStats:["hp":68,"attack":65,"defense":65,"special-attack":125,"special-defense":115,"speed":80],
            abilities:[.init(name:abilities[id] ?? "static",slot:1,isHidden:false)],
            moves:[.init(name:"psychic",learnMethods:[.init(method:"level-up",level:1)])])
    }
    func testEveryFairyMoveHasCompleteOfflineTranslationsAndEngineAlignedMetadata() throws {
        let extra=PokemonFairyMoves.shared,catalog=BattleTextCatalog.shared
        XCTAssertEqual(extra.moves.count,14);XCTAssertEqual(extra.learnsets.count,222)
        for (id,move) in extra.moves {
            XCTAssertEqual(move.type,"Fairy",id)
            XCTAssertNotNil(move.accuracy,id)
            for language in AppLanguage.allCases {
                let l=L(language)
                XCTAssertFalse(move.names[language.rawValue]?.isEmpty ?? true,id)
                XCTAssertFalse(move.descriptions[language.rawValue]?.isEmpty ?? true,id)
                XCTAssertNotEqual(catalog.moveName(id,language:language),l.battleUnknownMove)
                XCTAssertTrue(catalog.moveMenuTitle(id,language:language).contains(catalog.typeName("Fairy",language:language)))
                XCTAssertTrue(catalog.moveTooltip(id,language:language).contains(l.battleBaseAccuracy))
            }
        }
        for description in try XCTUnwrap(extra.moves["moonblast"]).descriptions.values {
            XCTAssertTrue(description.contains("30") || description.contains("３０"))
            XCTAssertFalse(description.contains("10") || description.contains("１０"))
        }
        XCTAssertEqual(catalog.moves["moonblast"]?.power,95)
        XCTAssertEqual(catalog.moves["lightofruin"]?.pp,5)
        XCTAssertEqual(catalog.moves["playrough"]?.category,"Physical")
        XCTAssertEqual(catalog.moves["disarmingvoice"]?.accuracy,.always)
    }
    func testBW2AndOfflineCachesGainOnlyCompatibleChoicesAtTheCorrectLevel() {
        let gardevoir=Self.details(282)
        XCTAssertFalse(PokemonLoadout.moveOptions(details:gardevoir,level:61).contains{$0.name=="moonblast"})
        let ready=PokemonLoadout.moveOptions(details:gardevoir,level:62)
        XCTAssertTrue(ready.contains{$0.name=="moonblast"})
        XCTAssertTrue(ready.contains{$0.name=="psychic"},"Keep existing BW2 moves")
        XCTAssertFalse(gardevoir.moves.contains{$0.name=="moonblast"},"Do not mutate API metadata or automatic caught moves")
        XCTAssertEqual(gardevoir.levelUpMoves(through:100).map(\.name),["psychic"])
        XCTAssertTrue(PokemonLoadout.moveOptions(details:Self.details(94),level:5).contains{$0.name=="dazzling-gleam"},"Inherited Gastly TM route")
        XCTAssertTrue(PokemonLoadout.moveOptions(details:Self.details(579),level:5).contains{$0.name=="light-of-ruin"},"Reviewed PokéRogue egg route")
        XCTAssertFalse(PokemonLoadout.moveOptions(details:Self.details(6),level:100).contains{$0.name=="moonblast"})
        for moves in PokemonFairyMoves.shared.learnsets.values {
            XCTAssertNil(moves["geomancy"]);XCTAssertNil(moves["fairy-lock"],"Do not invent Gen1–5 learners")
            XCTAssertTrue(Set(moves.keys.map(BattleTextCatalog.key)).isSubset(of:Set(PokemonFairyMoves.shared.moves.keys)))
        }
        let unchanged=PokemonProfile.generate(seed:7)
        XCTAssertNil(PokemonLoadout.replacingMove(unchanged,slot:0,name:"moonblast",details:Self.details(6)))
        var copy=gardevoir
        copy=PokemonDetails(speciesID:copy.speciesID,name:copy.name,height:copy.height,weight:copy.weight,baseExperience:copy.baseExperience,genderRate:copy.genderRate,types:copy.types,baseStats:copy.baseStats,abilities:copy.abilities,moves:copy.moves+[.init(name:"moon-blast",learnMethods:[.init(method:"machine",level:0)])])
        XCTAssertEqual(PokemonFairyMoves.mergedMoves(details:copy).filter{BattleTextCatalog.key($0.name)=="moonblast"}.count,1)
    }
    func testSelectedFairyMovesPersistWithoutChangingStatsAndPassRealBattlePreflight() async throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("fairy-loadout-\(UUID())")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:folder)}
        let suite="fairy-loadout-\(UUID())",defaults=try XCTUnwrap(UserDefaults(suiteName:suite))
        defer {defaults.removePersistentDomain(forName:suite)}
        let file=folder.appendingPathComponent("profile.json"),ids=[282,94,26,579,547,235]
        var state=CompanionState()
        state.dex=ids.map{id in
            var profile=PokemonProfile.generate(seed:UInt64(id));profile.level=100;profile.enrich(with:Self.details(id))
            return DexEntry(id:String(id),baseID:id,finalID:id,chainOrder:[id],rarity:.common,caughtAt:Date(),nature:.modest,profile:profile)
        }
        try JSONEncoder().encode(state).write(to:file)
        let store=CompanionStore(detailProvider:FairyDetailProvider(),fileURL:file,defaults:defaults)
        for id in ids {await store.loadPokemonDetails(speciesID:id)}
        let before=try XCTUnwrap(store.state.dex.first?.profile)
        XCTAssertTrue(store.setPokemonMove(entryID:"282",slot:0,name:"moonblast"))
        XCTAssertTrue(store.setPokemonMove(entryID:"94",slot:0,name:"dazzling-gleam"))
        XCTAssertTrue(store.setPokemonMove(entryID:"579",slot:0,name:"light-of-ruin"))
        XCTAssertFalse(store.setPokemonMove(entryID:"547",slot:0,name:"geomancy"))
        let restored=CompanionStore(detailProvider:FairyDetailProvider(),fileURL:file,defaults:defaults)
        let after=try XCTUnwrap(restored.state.dex.first?.profile)
        XCTAssertEqual(after.ivs,before.ivs);XCTAssertEqual(after.level,before.level);XCTAssertEqual(after.abilityName,before.abilityName)
        XCTAssertEqual(after.moves.first?.name,"moonblast")
        for mode in [BattleMode.singles,.doubles] {
            let team=try await BattleTeamBuilder.build(ids:ids.map(String.init),entries:restored.state.dex,mode:mode,language:.ko,provider:FairyDetailProvider())
            XCTAssertEqual(team.first?.moves.first,"moonblast")
            let abilities=try await BattleEngineProcess.validate(mode:mode,team:team)
            XCTAssertEqual(abilities.count,6)
        }
    }
}
