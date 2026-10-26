import XCTest
@testable import PokeTokenBar

private struct ModernRegistrationDetails:PokemonDetailProviding {
    func pokemonDetails(speciesID:Int) async throws -> PokemonDetails {
        let names=[26:"raichu",6:"charizard",9:"blastoise",3:"venusaur",94:"gengar",143:"snorlax"]
        let abilities=[26:"static",6:"blaze",9:"torrent",3:"overgrow",94:"cursed-body",143:"immunity"]
        return PokemonDetails(speciesID:speciesID,name:names[speciesID]!,height:10,weight:100,baseExperience:100,genderRate:4,types:["normal"],baseStats:["hp":100,"attack":100,"defense":100,"special-attack":100,"special-defense":100,"speed":100],abilities:[.init(name:abilities[speciesID]!,slot:1,isHidden:false)],moves:[])
    }
}
@MainActor final class BattleRegistrationCompatibilityTests:XCTestCase {
    func testModernCaughtAndPersistedDefaultAbilitiesUseHistoricalSlotsAcrossSpecies() throws {
        struct Case:Decodable{let id:Int;let name:String;let slot:Int;let hidden:Bool;let now:String;let then:String}
        let cases=try JSONDecoder().decode([Case].self,from:Data(#"[{"id":39,"name":"Jigglypuff","slot":2,"hidden":false,"now":"Competitive","then":"Cute Charm"},{"id":40,"name":"Wigglytuff","slot":2,"hidden":false,"now":"Competitive","then":"Cute Charm"},{"id":145,"name":"Zapdos","slot":3,"hidden":true,"now":"Static","then":"Lightning Rod"},{"id":174,"name":"Igglybuff","slot":2,"hidden":false,"now":"Competitive","then":"Cute Charm"},{"id":311,"name":"Plusle","slot":3,"hidden":true,"now":"Lightning Rod","then":"Plus"},{"id":312,"name":"Minun","slot":3,"hidden":true,"now":"Volt Absorb","then":"Minus"},{"id":352,"name":"Kecleon","slot":3,"hidden":true,"now":"Protean","then":"Color Change"},{"id":349,"name":"Feebas","slot":2,"hidden":false,"now":"Oblivious","then":"Swift Swim"},{"id":350,"name":"Milotic","slot":2,"hidden":false,"now":"Competitive","then":"Marvel Scale"},{"id":355,"name":"Duskull","slot":3,"hidden":true,"now":"Frisk","then":"Levitate"},{"id":356,"name":"Dusclops","slot":3,"hidden":true,"now":"Frisk","then":"Pressure"},{"id":393,"name":"Piplup","slot":3,"hidden":true,"now":"Competitive","then":"Defiant"},{"id":394,"name":"Prinplup","slot":3,"hidden":true,"now":"Competitive","then":"Defiant"},{"id":395,"name":"Empoleon","slot":3,"hidden":true,"now":"Competitive","then":"Defiant"},{"id":396,"name":"Starly","slot":3,"hidden":true,"now":"Reckless","then":"Keen Eye"},{"id":477,"name":"Dusknoir","slot":3,"hidden":true,"now":"Frisk","then":"Pressure"},{"id":526,"name":"Gigalith","slot":2,"hidden":false,"now":"Sand Stream","then":"Sturdy"},{"id":543,"name":"Venipede","slot":3,"hidden":true,"now":"Speed Boost","then":"Quick Feet"},{"id":544,"name":"Whirlipede","slot":3,"hidden":true,"now":"Speed Boost","then":"Quick Feet"},{"id":545,"name":"Scolipede","slot":3,"hidden":true,"now":"Speed Boost","then":"Quick Feet"},{"id":575,"name":"Gothorita","slot":2,"hidden":false,"now":"Competitive","then":"Frisk"},{"id":576,"name":"Gothitelle","slot":2,"hidden":false,"now":"Competitive","then":"Frisk"},{"id":598,"name":"Ferrothorn","slot":3,"hidden":true,"now":"Anticipation","then":"Iron Barbs"},{"id":607,"name":"Litwick","slot":3,"hidden":true,"now":"Infiltrator","then":"Shadow Tag"},{"id":608,"name":"Lampent","slot":3,"hidden":true,"now":"Infiltrator","then":"Shadow Tag"},{"id":609,"name":"Chandelure","slot":3,"hidden":true,"now":"Infiltrator","then":"Shadow Tag"},{"id":94,"name":"Gengar","slot":1,"hidden":false,"now":"Cursed Body","then":"Levitate"},{"id":243,"name":"Raikou","slot":3,"hidden":true,"now":"Inner Focus","then":"Volt Absorb"},{"id":244,"name":"Entei","slot":3,"hidden":true,"now":"Inner Focus","then":"Flash Fire"},{"id":245,"name":"Suicune","slot":3,"hidden":true,"now":"Inner Focus","then":"Water Absorb"},{"id":278,"name":"Wingull","slot":2,"hidden":false,"now":"Hydration","then":"Keen Eye"},{"id":279,"name":"Pelipper","slot":2,"hidden":false,"now":"Drizzle","then":"Keen Eye"},{"id":324,"name":"Torkoal","slot":2,"hidden":false,"now":"Drought","then":"White Smoke"},{"id":524,"name":"Roggenrola","slot":2,"hidden":false,"now":"Weak Armor","then":"Sturdy"},{"id":525,"name":"Boldore","slot":2,"hidden":false,"now":"Weak Armor","then":"Sturdy"},{"id":582,"name":"Vanillite","slot":2,"hidden":false,"now":"Snow Cloak","then":"Ice Body"},{"id":583,"name":"Vanillish","slot":2,"hidden":false,"now":"Snow Cloak","then":"Ice Body"},{"id":584,"name":"Vanilluxe","slot":2,"hidden":false,"now":"Snow Warning","then":"Ice Body"},{"id":613,"name":"Cubchoo","slot":2,"hidden":false,"now":"Slush Rush","then":"Snow Cloak"},{"id":614,"name":"Beartic","slot":2,"hidden":false,"now":"Slush Rush","then":"Snow Cloak"},{"id":109,"name":"Koffing","slot":2,"hidden":false,"now":"Neutralizing Gas","then":"Levitate"},{"id":109,"name":"Koffing","slot":3,"hidden":true,"now":"Stench","then":"Levitate"},{"id":110,"name":"Weezing","slot":2,"hidden":false,"now":"Neutralizing Gas","then":"Levitate"},{"id":110,"name":"Weezing","slot":3,"hidden":true,"now":"Stench","then":"Levitate"},{"id":475,"name":"Gallade","slot":2,"hidden":false,"now":"Sharpness","then":"Steadfast"},{"id":275,"name":"Shiftry","slot":2,"hidden":false,"now":"Wind Rider","then":"Early Bird"}]"#.utf8))
        for item in cases {
            let details=PokemonDetails(speciesID:item.id,name:item.name,height:10,weight:100,baseExperience:100,genderRate:4,types:["normal"],baseStats:["hp":100],abilities:[.init(name:item.now,slot:item.slot,isHidden:item.hidden)],moves:[])
            for legacy in [false,true] {
                var profile=PokemonProfile.generate(seed:UInt64(item.id));profile.level=50
                if legacy{profile.abilityName=item.now;profile.abilitySlot=item.slot;profile.abilityIsHidden=item.hidden}
                let ivs=profile.ivs
                profile.enrich(with:details)
                XCTAssertEqual(BattleTextCatalog.key(profile.abilityName ?? ""),BattleTextCatalog.key(item.then),item.name)
                XCTAssertEqual(profile.ivs,ivs);XCTAssertEqual(profile.level,50)
            }
        }
    }
    func testCompleteSavedGengarLoadoutRegistersSixAndStartsSinglesAndDoubles() async throws {
        let provider=ModernRegistrationDetails()
        var entries:[DexEntry]=[]
        for id in [26,6,9,3,94,143] {
            let details=try await provider.pokemonDetails(speciesID:id)
            var profile=PokemonProfile.generate(seed:UInt64(id));profile.level=50
            profile.abilityName=details.abilities[0].name;profile.abilitySlot=1
            profile.moves=[.init(name:"protect",learnedAtLevel:1)]
            entries.append(DexEntry(id:"registration-\(id)",baseID:id,finalID:id,chainOrder:[id],rarity:.common,caughtAt:Date(),profile:profile))
        }
        for mode in BattleMode.allCases {
            let team=try await BattleTeamBuilder.build(ids:entries.map(\.id),entries:entries,mode:mode,language:.ko,provider:provider)
            XCTAssertEqual(team.count,6);XCTAssertEqual(team[4].ability,"Levitate")
            XCTAssertEqual(team[4].moves,["protect"])
            let engine=BattleEngineProcess();defer{engine.stop()}
            let ordered=[team[4]]+team.enumerated().filter{$0.offset != 4}.map(\.element)
            var frames:[BattleFrame]=[]
            try engine.start(mode:mode,teams:[ordered,ordered])
            engine.onFrames={frames=$0}
            let end=Date().addingTimeInterval(10)
            while frames.isEmpty,Date()<end{try await Task.sleep(for:.milliseconds(20))}
            XCTAssertEqual(frames.count,2)
            XCTAssertEqual(frames.first?.own.first?.speciesID,94)
            XCTAssertEqual(BattleTextCatalog.key(frames.first?.own.first?.ability ?? ""),"levitate")
            XCTAssertEqual(frames.first?.own.first?.stats,team[4].stats)
        }
        XCTAssertEqual(entries[4].profile?.abilityName,"cursed-body","Building must not overwrite the saved collection")
    }
    func testRegistrationItemsReachRealSinglesAndDoublesMegaRequests() async throws {
        let provider=ModernRegistrationDetails();var entries:[DexEntry]=[]
        for id in [6,26,9,3,94,143] {
            let details=try await provider.pokemonDetails(speciesID:id)
            var profile=PokemonProfile.generate(seed:UInt64(id));profile.level=50
            profile.abilityName=details.abilities[0].name;profile.abilitySlot=1
            profile.moves=[.init(name:"protect",learnedAtLevel:1)]
            entries.append(DexEntry(id:"item-registration-\(id)",baseID:id,finalID:id,chainOrder:[id],rarity:.common,caughtAt:Date(),nature:.adamant,profile:profile))
        }
        let items=["charizarditex","sitrusberry","lumberry","leftovers","lifeorb","focussash"]
        let assignments=Dictionary(uniqueKeysWithValues:zip(entries.map(\.id),items))
        for mode in BattleMode.allCases {
            let team=try await BattleTeamBuilder.build(ids:entries.map(\.id),entries:entries,mode:mode,language:.ko,provider:provider,heldItems:assignments)
            XCTAssertEqual(team.map{$0.item ?? ""},items)
            let restored=try JSONDecoder().decode([BattlePokemon].self,from:JSONEncoder().encode(team));XCTAssertEqual(restored,team)
            let engine=BattleEngineProcess();defer{engine.stop()};var frames:[BattleFrame]=[]
            try engine.start(mode:mode,teams:[team,team]);engine.onFrames={frames=$0}
            let start=Date().addingTimeInterval(10)
            while frames.isEmpty,Date()<start {try await Task.sleep(for:.milliseconds(20))}
            XCTAssertEqual(frames.count,2);guard frames.count==2 else{continue}
            XCTAssertEqual(frames[0].own[0].stats,team[0].stats);XCTAssertTrue(frames[0].slots[0].canMegaEvo==true)
            let initial=frames
            for p in [0,1] {
                let actions=initial[p].slots.map{slot in BattleAction(kind:"move",index:1,target:0,mega:slot.slot==0 ? true:nil)}
                try engine.choose(player:p,decision:BattleDecision(decisionID:initial[p].decisionID,actions:actions,order:[]))
            }
            let end=Date().addingTimeInterval(10)
            while frames.first?.own[0].mega != true,Date()<end {try await Task.sleep(for:.milliseconds(20))}
            XCTAssertEqual(frames.first?.own[0].form?.rawValue,"mega-x")
            XCTAssertEqual(frames.first?.own[0].maxHP,team[0].stats["hp"])
            XCTAssertEqual(frames.first?.own[0].hp,team[0].stats["hp"])
            XCTAssertEqual(frames.first?.own[0].ability,"Tough Claws")
            XCTAssertTrue(frames.first?.slots.allSatisfy{$0.canMegaEvo != true}==true)
        }
        let unassigned=try await BattleTeamBuilder.build(ids:entries.map(\.id),entries:entries,mode:.singles,language:.ko,provider:provider)
        XCTAssertTrue(unassigned.allSatisfy{$0.item == nil || $0.item == ""})
        do {
            var duplicates=assignments;duplicates[entries[5].id]="charizarditex"
            _ = try await BattleTeamBuilder.build(ids:entries.map(\.id),entries:entries,mode:.singles,language:.ko,provider:provider,heldItems:duplicates)
            XCTFail("The sixth reserve must still obey the item clause")
        } catch {XCTAssertEqual(error.localizedDescription,L(.ko).battleDuplicateItem)}
    }

}
