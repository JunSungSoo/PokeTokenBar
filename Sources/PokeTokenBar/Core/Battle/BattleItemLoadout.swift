import Foundation
import Observation

/// A match-local assignment, independent of collection profiles and pending row previews.
struct BattleItemLoadout:Sendable {
    private(set) var items:[String:String]=[:]
    mutating func retain(_ roster:[String]) {items=items.filter{roster.contains($0.key)}}
    /// Restore in registration order, never dictionary or collection order.
    /// Conflicting defaults remain remembered, but only the first holder equips them.
    mutating func restore(roster:[DexEntry],remembered:[String:String],overrides:[String:String]=[:],useCollectionDefaults:Bool=true) {
        items=[:]
        let ids=roster.map(\.id)
        for entry in roster {
            let preferred=useCollectionDefaults ? entry.battleDefaultItem.flatMap { id in
                BattleHeldItems.choices(speciesID:entry.finalID,form:entry.form).contains(where:{$0.id==id}) ? id:nil
            }:nil
            _ = apply(overrides[entry.id] ?? preferred ?? remembered[entry.id] ?? "",to:entry,roster:ids)
        }
    }
    func owner(of itemID:String,excluding pokemonID:String?=nil)->String? {
        guard !itemID.isEmpty else{return nil}
        return items.keys.sorted().first{$0 != pokemonID && items[$0]==itemID}
    }
    func canApply(_ itemID:String,to entry:DexEntry,roster:[String])->Bool {
        guard roster.contains(entry.id),!entry.isReleased else{return false}
        guard itemID.isEmpty || BattleHeldItems.choices(speciesID:entry.finalID,form:entry.form).contains(where:{$0.id==itemID}) else{return false}
        return !roster.contains(where:{$0 != entry.id && items[$0]==itemID && !itemID.isEmpty})
    }
    @discardableResult mutating func apply(_ itemID:String,to entry:DexEntry,roster:[String])->Bool {
        guard canApply(itemID,to:entry,roster:roster) else{return false}
        retain(roster)
        if itemID.isEmpty {items.removeValue(forKey:entry.id)} else {items[entry.id]=itemID}
        return true
    }
}

/// Explicit Apply choices belong to an owned individual, not a species or consumed battle item.
/// Automatic duplicate/compatibility fallbacks must not erase that individual's last choice.
@MainActor final class BattlePokemonItemStore {
    static let shared=BattlePokemonItemStore()
    private let defaults:UserDefaults
    private let key="battlePokemonHeldItems.v1"
    private(set) var items:[String:String]
    init(defaults:UserDefaults = .standard) {
        self.defaults=defaults
        items=defaults.data(forKey:key).flatMap{try? JSONDecoder().decode([String:String].self,from:$0)} ?? [:]
    }
    func recordApplied(_ itemID:String,to entry:DexEntry) {
        guard !entry.isReleased,itemID.isEmpty || BattleHeldItems.choices(speciesID:entry.finalID,form:entry.form).contains(where:{$0.id==itemID}) else{return}
        items[entry.id]=itemID
        if let data=try? JSONEncoder().encode(items){defaults.set(data,forKey:key)}
    }
}

/// Recency is an applied selection, not opening/previewing a row. One atomic local record.
@MainActor @Observable final class BattleItemUsageStore {
    struct Usage:Codable,Equatable {var count:Int;var order:Int}
    private struct State:Codable {var sequence=0;var items:[String:Usage]=[:]}
    static let shared=BattleItemUsageStore()
    private let defaults:UserDefaults
    private let key="battleHeldItemUsage.v1"
    private var state:State
    init(defaults:UserDefaults = .standard) {
        self.defaults=defaults
        state=defaults.data(forKey:key).flatMap{try? JSONDecoder().decode(State.self,from:$0)} ?? State()
    }
    func usage(_ id:String)->Usage? {state.items[id]}
    func recordApplied(_ id:String) {
        guard BattleHeldItems.item(id) != nil else{return}
        state.sequence += 1
        state.items[id]=Usage(count:(state.items[id]?.count ?? 0)+1,order:state.sequence)
        if let data=try? JSONEncoder().encode(state){defaults.set(data,forKey:key)}
    }
    func sorted(_ items:[BattleHeldItem],language:AppLanguage)->[BattleHeldItem] {
        items.sorted {a,b in
            let x=state.items[a.id],y=state.items[b.id]
            let usedX=(x?.count ?? 0)>0,usedY=(y?.count ?? 0)>0
            if usedX != usedY{return usedX}
            if usedX,x?.order != y?.order{return (x?.order ?? 0)>(y?.order ?? 0)}
            let comparison=a.name(language).compare(b.name(language),options:[.caseInsensitive,.diacriticInsensitive,.numeric],range:nil,locale:language.displayLocale)
            return comparison == .orderedSame ? a.id<b.id:comparison == .orderedAscending
        }
    }
}

extension BattleHeldItems {
    static func hasDuplicates(_ team:[BattlePokemon])->Bool {
        let ids=team.compactMap(\.item).map(BattleTextCatalog.key).filter{!$0.isEmpty}
        return Set(ids).count != ids.count
    }
}

extension L {
    var battleChooseItem:String {t("도구 선택","Choose item","道具を選ぶ","Elegir objeto","Choisir un objet","Escolher item","Item wählen","Выбрать предмет")}
    var battleApplyItem:String {t("적용","Apply","適用","Aplicar","Appliquer","Aplicar","Anwenden","Применить")}
    var battleDuplicateItem:String {t("같은 팀의 6마리는 동일한 도구를 중복해서 지닐 수 없습니다.","The six team members cannot hold duplicate items.","6匹のチームで同じ道具を重複して持てません。","Los seis miembros no pueden llevar objetos repetidos.","Les six membres ne peuvent pas tenir d’objets identiques.","Os seis membros não podem equipar itens repetidos.","Die sechs Teammitglieder dürfen keine identischen Items tragen.","У шести членов команды не может быть одинаковых предметов.")}
    var battleItemOrderHint:String {t("최근 적용순 · 미사용 도구는 이름순","Recently applied first · Unused items by name","最近の適用順・未使用は名前順","Aplicados recientemente primero · Sin usar por nombre","Derniers appliqués d’abord · Inutilisés par nom","Aplicados recentemente primeiro · Não usados por nome","Zuletzt angewendet zuerst · Ungenutzte nach Name","Сначала недавно применённые · Неиспользованные по имени")}
    var battleItemPreviewHint:String {t("도구를 선택해 설명을 확인한 뒤 적용을 누르세요.","Select an item to read its description, then press Apply.","道具を選んで説明を確認し、適用してください。","Selecciona un objeto, lee su descripción y pulsa Aplicar.","Choisis un objet, lis sa description puis applique-le.","Escolha um item, leia a descrição e pressione Aplicar.","Wähle ein Item, lies die Beschreibung und klicke Anwenden.","Выберите предмет, прочтите описание и нажмите «Применить».")}
    var battleItemEquipped:String {t("장착됨","Equipped","装備中","Equipado","Équipé","Equipado","Ausgerüstet","Экипирован")}
    var battleItemInUse:String {t("다른 포켓몬이 사용 중","Used by another Pokémon","他のポケモンが使用中","Lo usa otro Pokémon","Utilisé par un autre Pokémon","Usado por outro Pokémon","Von anderem Pokémon getragen","Использует другой покемон")}
}

extension L {
    var collectionDefaultItem:String {t("기본 배틀 도구","Default battle item","バトルの既定の道具","Objeto de combate predeterminado","Objet de combat par défaut","Item de batalha padrão","Standard-Kampfitem","Предмет для боя по умолчанию")}
    var collectionDefaultItemHint:String {t("컬렉션 도구를 우선 장착합니다. 없으면 최근 배틀 도구를 사용합니다.","Use the collection item first; otherwise use the last battle item.","コレクションの道具を優先し、未設定なら前回のバトルの道具を使います。","Se usa primero el objeto de la colección; si no hay, el del último combate.","L’objet de la collection est prioritaire, sinon celui du dernier combat est utilisé.","O item da coleção tem prioridade; caso não haja, usa o da última batalha.","Das Sammlungsitem hat Vorrang, sonst wird das zuletzt im Kampf verwendete Item genutzt.","Сначала используется предмет из коллекции, иначе — из последнего боя.")}
    var pokemonStatGradeHint:String {t("개체값 등급: 1~32 (높을수록 우수)","IV grade: 1–32 (higher is better)","個体値の評価：1～32（高いほど優秀）","Grado de IV: 1–32 (más alto es mejor)","Note d’IV : 1–32 (plus élevée = meilleure)","Grau de IV: 1–32 (maior é melhor)","DV-Bewertung: 1–32 (höher ist besser)","Оценка IV: 1–32 (выше — лучше)")}
}
