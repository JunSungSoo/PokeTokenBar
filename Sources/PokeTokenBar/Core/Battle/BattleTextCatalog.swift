import Foundation

/// Battle presentation never falls back to another language or a raw simulator identifier.
/// The checked-in catalog also covers API outages and languages absent from PokéAPI.
struct BattleTextCatalog: Decodable, Sendable {
    struct Move: Decodable, Sendable {
        let names: [String:String]
        let descriptions: [String:String]
        let power: Int?
        let pp: Int?
        let category: String?
        let type: String?
        let accuracy: BattleMoveAccuracy?
    }
    let moves: [String:Move]
    let species: [String:[String:String]]
    let aliases: [String:String]
    let abilities: [String:[String:String]]
    let abilityDescriptions: [String:[String:String]]?
    let types: [String:[String:String]]
    static let shared: BattleTextCatalog = {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("BattleText/catalog.json")
        let url = bundled.flatMap { FileManager.default.fileExists(atPath:$0.path) ? $0 : nil }
            ?? Bundle.module.url(forResource:"catalog",withExtension:"json",subdirectory:"BattleText")!
        // A missing/incomplete resource is a build error, caught by catalog/packaging tests.
        let base=try! JSONDecoder().decode(Self.self,from:Data(contentsOf:url))
        return Self(moves:base.moves.merging(PokemonFairyMoves.shared.moves){_,new in new},
            species:base.species,aliases:base.aliases,abilities:base.abilities,
            abilityDescriptions:base.abilityDescriptions,
            types:base.types.merging(PokemonFairyMoves.shared.types){_,new in new})
    }()
    private static let speciesTypes: [String:[String]] = {
        let bundled=Bundle.main.resourceURL?.appendingPathComponent("BattleText/species-types.json")
        let url=bundled.flatMap { FileManager.default.fileExists(atPath:$0.path) ? $0:nil }
            ?? Bundle.module.url(forResource:"species-types",withExtension:"json",subdirectory:"BattleText")!
        return try! JSONDecoder().decode([String:[String]].self,from:Data(contentsOf:url))
    }()
    static let moveTargets: [String:String] = {
        let bundled=Bundle.main.resourceURL?.appendingPathComponent("BattleText/move-targets.json")
        let url=bundled.flatMap { FileManager.default.fileExists(atPath:$0.path) ? $0:nil }
            ?? Bundle.module.url(forResource:"move-targets",withExtension:"json",subdirectory:"BattleText")!
        return try! JSONDecoder().decode([String:String].self,from:Data(contentsOf:url))
    }()
    func pokemonTypes(_ id:Int,form:PokemonForm?)->[String] {
        let form=PokemonForm.resolved(speciesID:id,form:form)
        let key=String(id)+(form.map{":"+$0.rawValue} ?? "")
        return Self.speciesTypes[key] ?? Self.speciesTypes[String(id)] ?? []
    }
    func speciesTypeNames(_ id:Int,form:PokemonForm?,language:AppLanguage)->String {
        (BattleHeldItems.mega(speciesID:id,form:form)?.types ?? pokemonTypes(id,form:form)).map{typeName($0,language:language)}.joined(separator:" / ")
    }
    static func key(_ raw: String) -> String {
        raw.replacingOccurrences(of:"♀",with:"f").replacingOccurrences(of:"♂",with:"m")
            .lowercased().unicodeScalars.filter { (97...122).contains($0.value) || (48...57).contains($0.value) }.map(String.init).joined()
    }
    func speciesName(_ id: Int, language: AppLanguage) -> String {
        species[String(id)]?[language.rawValue] ?? L(language).battleUnknownPokemon
    }
    func pokemonName(_ raw: String, language: AppLanguage) -> String {
        let bare = raw.components(separatedBy:": ").last?.components(separatedBy:",").first ?? raw
        if let mega=BattleHeldItems.all.compactMap(\.mega).first(where:{$0.species.lowercased()==bare.lowercased()}) {
            return L(language).battleMegaEvolution+" · "+speciesName(mega.baseID,language:language)+(mega.form=="mega" ? "":" "+mega.form.replacingOccurrences(of:"mega-",with:"").uppercased())
        }
        return aliases[Self.key(bare)].flatMap { species[$0]?[language.rawValue] } ?? L(language).battleUnknownPokemon
    }
    func moveName(_ raw: String, language: AppLanguage) -> String {
        moves[Self.key(raw)]?.names[language.rawValue] ?? L(language).battleUnknownMove
    }
    func moveMenuTitle(_ raw: String, language: AppLanguage) -> String {
        moveName(raw, language: language) + " · "
            + typeName(moves[Self.key(raw)]?.type ?? "", language: language)
            + " · " + L(language).battleCategory(moves[Self.key(raw)]?.category ?? "")
    }
    func description(_ raw: String, language: AppLanguage) -> String {
        moves[Self.key(raw)]?.descriptions[language.rawValue] ?? L(language).battleDescriptionUnavailable
    }
    func typeName(_ raw: String, language: AppLanguage) -> String {
        types[Self.key(raw)]?[language.rawValue] ?? BattleMegaText.catalog.types[Self.key(raw)]?[language.rawValue] ?? L(language).battleUnknownType
    }
    func abilityName(_ raw: String, language: AppLanguage) -> String {
        abilities[Self.key(raw)]?[language.rawValue] ?? BattleMegaText.catalog.abilities[Self.key(raw)]?.names[language.rawValue] ?? L(language).battleAbility
    }
    func abilityDescription(_ raw: String, language: AppLanguage) -> String {
        abilityDescriptions?[Self.key(raw)]?[language.rawValue] ?? BattleMegaText.catalog.abilities[Self.key(raw)]?.descriptions[language.rawValue] ?? L(language).battleDescriptionUnavailable
    }
    func moveTooltip(_ raw: String, language: AppLanguage) -> String {
        let l = L(language)
        var lines = [moveName(raw, language: language), description(raw, language: language)]
        if let move = moves[Self.key(raw)], let type = move.type, let category = move.category,
           let pp = move.pp, let power = move.power {
            lines.append("\(typeName(type, language: language)) · \(l.battleCategory(category)) · \(l.battlePower): \(power > 0 ? String(power) : "—") · \(l.battlePP): \(pp)")
        }
        lines.append(l.battleBaseAccuracy + ": " + l.battleAccuracy(moves[Self.key(raw)]?.accuracy))
        let scope=Self.moveTargets[Self.key(raw)]
        lines.append(l.battleTarget + ": " + l.battleMoveTarget(scope:scope,includesAllies:scope == "normal" || scope == "any"))
        return lines.joined(separator: "\n")
    }
    func abilityTooltip(_ raw: String, language: AppLanguage) -> String {
        abilityName(raw, language: language) + "\n" + abilityDescription(raw, language: language)
    }
    func effectName(_ raw: String, language: AppLanguage) -> String {
        let bare = raw.components(separatedBy:": ").last ?? raw
        if let item=BattleHeldItems.item(bare) {return item.name(language)}
        if raw.lowercased().hasPrefix("ability:") { return abilityName(bare, language: language) }
        if let move = moves[Self.key(bare)] { return move.names[language.rawValue] ?? L(language).battleUnknownMove }
        if abilities[Self.key(bare)] != nil || BattleMegaText.catalog.abilities[Self.key(bare)] != nil { return abilityName(bare, language: language) }
        return L(language).battleStatus(Self.key(bare))
    }
}
