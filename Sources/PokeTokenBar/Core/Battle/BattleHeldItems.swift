import Foundation

struct BattleHeldItem:Codable,Sendable,Identifiable {
    struct Mega:Codable,Sendable {
        let baseID:Int
        let base:String
        let species:String
        let form:String
        let types:[String]
        let ability:String
        let stats:[String:Int]
        let pokemonID:Int
    }
    let id:String
    let group:String
    let names:[String:String]
    let descriptions:[String:String]
    let mega:Mega?
    func name(_ language:AppLanguage)->String { names[language.rawValue]! }
    func tooltip(_ language:AppLanguage)->String { name(language)+"\n"+descriptions[language.rawValue]! }
}
/// The picker categories mirror the shared item catalog without changing item rules.
enum BattleItemCategory:String,CaseIterable,Identifiable,Sendable {
    case all,mega,recovery,power,type,defense,order,berries
    var id:String {rawValue}
    func includes(_ item:BattleHeldItem)->Bool {self == .all || item.group == rawValue}
    func title(_ language:AppLanguage)->String {
        let l=L(language)
        switch self {
        case .all:return l.t("전체","All","すべて","Todos","Tous","Todos","Alle","Все")
        case .mega:return l.t("메가스톤","Mega Stones","メガストーン","Megapiedras","Méga-Gemmes","Megapedras","Mega-Steine","Мегакамни")
        case .recovery:return l.t("회복","Recovery","回復","Recuperación","Soin","Recuperação","Heilung","Восстановление")
        case .power:return l.t("공격강화","Attack boosts","攻撃強化","Potencia","Puissance","Poder","Angriffsverstärkung","Усиление атак")
        case .type:return l.t("타입강화","Type boosts","タイプ強化","Tipos","Types","Tipos","Typverstärkung","Усиление типов")
        case .defense:return l.t("생존","Survival","生存","Supervivencia","Survie","Sobrevivência","Überleben","Выживание")
        case .order:return l.t("행동순서","Turn order","行動順","Orden de turno","Ordre du tour","Ordem do turno","Zugreihenfolge","Порядок ходов")
        case .berries:return l.t("열매","Berries","きのみ","Bayas","Baies","Frutas","Beeren","Ягоды")
        }
    }
}

/// Shared with the authoritative helper; only the requested items are selectable/legal.
enum BattleHeldItems {
    private struct Catalog:Decodable {let items:[BattleHeldItem]}
    static let all:[BattleHeldItem] = {
        let bundled=Bundle.main.resourceURL?.appendingPathComponent("BattleText/held-items.json")
        let url=bundled.flatMap{FileManager.default.fileExists(atPath:$0.path) ? $0:nil}
            ?? Bundle.module.url(forResource:"held-items",withExtension:"json",subdirectory:"BattleText")!
        return try! JSONDecoder().decode(Catalog.self,from:Data(contentsOf:url)).items
    }()
    private static let byID=Dictionary(uniqueKeysWithValues:all.map{($0.id,$0)})
    private static let byForm=Dictionary(uniqueKeysWithValues:all.compactMap { item -> (String,BattleHeldItem.Mega)? in
        guard let mega=item.mega else{return nil};return (String(mega.baseID)+":"+mega.form,mega)
    })
    private static let megaFormsBySpecies=Dictionary(grouping:all.compactMap(\.mega),by:{$0.baseID}).mapValues{$0.map{PokemonForm($0.form)}}
    static func sizingForms(speciesID:Int)->[PokemonForm?] {
        let normal=PokemonForm.forms(speciesID:speciesID)
        return (normal.isEmpty ? [nil]:normal.map(Optional.some))+(megaFormsBySpecies[speciesID] ?? []).map(Optional.some)
    }
    static func item(_ raw:String?)->BattleHeldItem? {
        guard let raw else{return nil};let key=BattleTextCatalog.key(raw)
        return byID[key]
    }
    static func choices(speciesID:Int,form:PokemonForm?)->[BattleHeldItem] {
        all.filter{ item in
            guard let mega=item.mega else{return true}
            return mega.baseID==speciesID && PokemonForm.isDefault(form,speciesID:speciesID)
        }
    }
    static func mega(speciesID:Int,form:PokemonForm?)->BattleHeldItem.Mega? {
        guard let form else{return nil}
        return byForm[String(speciesID)+":"+form.rawValue]
    }
}

extension L {
    var battleHeldItem:String { t("지닌도구","Held item","持ち物","Objeto equipado","Objet tenu","Item equipado","Getragenes Item","Предмет") }
    var battleNoItem:String { t("없음","None","なし","Ninguno","Aucun","Nenhum","Keines","Нет") }
    var battleItemConsumed:String { t("소모됨","Consumed","消費","Consumido","Consommé","Consumido","Verbraucht","Израсходован") }
    var battleMegaEvolution:String { t("메가진화","Mega Evolution","メガシンカ","Megaevolución","Méga-Évolution","Mega Evolução","Mega-Entwicklung","Мегаэволюция") }
    var battleHeldItemHint:String { t("배틀 중 소모된 도구는 다음 배틀에서 복구됩니다.","Items consumed in battle return for the next battle.","消費した道具は次のバトルで戻ります。","Los objetos consumidos vuelven para el próximo combate.","Les objets consommés reviennent au prochain combat.","Itens consumidos voltam na próxima batalha.","Verbrauchte Items sind im nächsten Kampf wieder verfügbar.","Израсходованные предметы возвращаются к следующему бою.") }
}

/// Form artwork is battle-only; no additional hatchable/collectible forms are introduced.
enum BattleMegaSprites {
    struct Record:Decodable,Sendable {let file:String;let animated:Bool;let sha256:String}
    static var directory:URL {
        let bundled=Bundle.main.resourceURL?.appendingPathComponent("PokeRoguePlayer/mega-sprites")
        if let bundled,FileManager.default.fileExists(atPath:bundled.appendingPathComponent("manifest.json").path){return bundled}
        return Bundle.module.url(forResource:"PokeRoguePlayer",withExtension:nil)!.appendingPathComponent("mega-sprites")
    }
    static let records:[String:Record] = {
        guard let data=try? Data(contentsOf:directory.appendingPathComponent("manifest.json")) else{return [:]}
        return (try? JSONDecoder().decode([String:Record].self,from:data)) ?? [:]
    }()
    static func record(speciesID:Int,form:PokemonForm?,back:Bool,shiny:Bool)->Record? {
        guard let mega=BattleHeldItems.mega(speciesID:speciesID,form:form) else{return nil}
        return records[(back ? "back-":"")+String(speciesID)+"-"+mega.form+(shiny ? "-sh":"")]
    }
}

enum BattleMegaText {
    struct Ability:Decodable,Sendable {let names:[String:String];let descriptions:[String:String]}
    struct Catalog:Decodable,Sendable {let abilities:[String:Ability];let types:[String:[String:String]]}
    static let catalog:Catalog = {
        let bundled=Bundle.main.resourceURL?.appendingPathComponent("BattleText/mega-text.json")
        let url=bundled.flatMap{FileManager.default.fileExists(atPath:$0.path) ? $0:nil}
            ?? Bundle.module.url(forResource:"mega-text",withExtension:"json",subdirectory:"BattleText")!
        return try! JSONDecoder().decode(Catalog.self,from:Data(contentsOf:url))
    }()
}
