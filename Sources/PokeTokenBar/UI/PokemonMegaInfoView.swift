import SwiftUI

/// Uses the same pinned forms, abilities, stats and artwork as the battle engine.
/// Viewing a form never changes an owned Pokémon or registers it as collected.
@MainActor
struct PokemonMegaInfoView:View {
    let speciesID:Int
    let language:AppLanguage
    var shiny=false
    var baseStats:[String:Int]=[:]
    var profile:PokemonProfile?
    var nature:PokemonNature?
    let onClose:()->Void
    @State private var selectedID=""
    private var l:L {L(language)}
    private var catalog:BattleTextCatalog {BattleTextCatalog.shared}
    private var stones:[BattleHeldItem] {BattleHeldItems.megaStones(speciesID:speciesID)}
    private var selected:BattleHeldItem? {stones.first{$0.id==selectedID} ?? stones.first}
    private let statKeys=[("hp","hp"),("attack","atk"),("defense","def"),("special-attack","spa"),("special-defense","spd"),("speed","spe")]
    var currentStats:[String:Int] {
        guard let profile,!baseStats.isEmpty else{return [:]}
        return Dictionary(uniqueKeysWithValues:PokemonStatCalculator.stats(baseStats:baseStats,speciesID:speciesID,profile:profile,nature:nature).map{($0.name,$0.value)})
    }
    func displayedStats(_ mega:BattleHeldItem.Mega)->[String:Int] {
        guard let profile,!currentStats.isEmpty else{return mega.stats}
        let bases=Dictionary(uniqueKeysWithValues:statKeys.compactMap {stat in mega.stats[stat.1].map{(stat.0,$0)} })
        var values=Dictionary(uniqueKeysWithValues:PokemonStatCalculator.stats(baseStats:bases,speciesID:speciesID,profile:profile,nature:nature).compactMap {stat in
            BattleTeamBuilder.statNames[stat.name].map{($0,stat.value)}
        })
        values["hp"]=currentStats["hp"]
        return values
    }

    var body:some View {
        VStack(spacing:12) {
            HStack {
                Text(l.pokemonMegaInfo).font(.headline)
                Spacer()
                Button(l.close,action:onClose).keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("pokemon-mega-info-close")
            }
            if stones.count>1 {
                Picker(l.battleMegaEvolution,selection:Binding(get:{selected?.id ?? ""},set:{selectedID=$0})) {
                    ForEach(stones) {stone in
                        Text(formTitle(stone.mega!.form)).tag(stone.id)
                    }
                }.pickerStyle(.segmented).accessibilityIdentifier("pokemon-mega-info-forms")
            }
            ScrollView {
                if let stone=selected,let mega=stone.mega {
                    VStack(alignment:.leading,spacing:14) {
                        VStack(spacing:8) {
                            SpriteView(speciesID:speciesID,size:140,animated:true,shiny:shiny,form:PokemonForm(mega.form))
                                .id(stone.id+"-"+String(shiny)).accessibilityLabel(catalog.pokemonName(mega.species,language:language))
                            Text(catalog.pokemonName(mega.species,language:language)).font(.title3.bold())
                            HStack(spacing:6) {
                                ForEach(mega.types,id:\.self) {type in
                                    Badge(tint:.type(PokemonType(apiName:type.lowercased())),size:11,horizontalPadding:8,verticalPadding:3) {
                                        Text(catalog.typeName(type,language:language))
                                    }
                                }
                            }
                        }.frame(maxWidth:.infinity)
                        VStack(alignment:.leading,spacing:4) {
                            Text(l.battleHeldItem).font(.caption).foregroundStyle(.secondary)
                            Text(stone.name(language)).font(.callout.bold()).help(stone.tooltip(language))
                            Text(l.ability).font(.caption).foregroundStyle(.secondary).padding(.top,4)
                            Text(catalog.abilityName(mega.ability,language:language)).font(.callout.bold())
                            Text(catalog.abilityDescription(mega.ability,language:language)).font(.caption)
                                .foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                        }
                        Divider()
                        VStack(spacing:7) {
                            let values=displayedStats(mega)
                            let current=currentStats
                            Text(current.isEmpty ? l.baseStats:l.actualStats).font(.headline).frame(maxWidth:.infinity,alignment:.leading)
                            if !baseStats.isEmpty {
                                Text(current.isEmpty ? l.pokemonMegaStatsComparison:l.pokemonMegaCurrentStatsComparison).font(.caption2).foregroundStyle(.secondary)
                                    .frame(maxWidth:.infinity,alignment:.leading)
                            }
                            ForEach(statKeys,id:\.0) {stat in
                                if let value=values[stat.1] {
                                    HStack(spacing:8) {
                                        Text(l.statLabel(stat.0)).frame(width:74,alignment:.leading)
                                        ProgressView(value:Double(value),total:Double(PokemonStatCalculator.displayScaleMaximum(for:Array(values.values)))).tint(.accentColor)
                                        Text(current[stat.0].map{"\($0) → \(value)"} ?? String(value)).monospacedDigit()
                                            .frame(width:current.isEmpty ? 30:100,alignment:.trailing)
                                        if let base=current[stat.0] ?? baseStats[stat.0] {
                                            let delta=value-base
                                            Text(delta>0 ? "+\(delta)":"\(delta)")
                                                .foregroundStyle(delta>0 ? Color.green:delta<0 ? Color.blue:Color.secondary)
                                                .monospacedDigit().frame(width:34,alignment:.trailing)
                                        }
                                    }.font(.system(size:12)).accessibilityIdentifier("pokemon-mega-stat-"+stat.0)
                                }
                            }
                            if current.isEmpty {
                                HStack {Text(l.baseStatTotal);Spacer();Text(String(mega.stats.values.reduce(0,+))).monospacedDigit().bold()}
                                    .font(.callout).padding(.top,4)
                            }
                        }
                    }.padding(.trailing,6)
                }
            }
        }.padding(18).frame(width:440,height:590)
            .environment(\.locale,language.displayLocale)
    }
    private func formTitle(_ form:String)->String {
        l.battleMegaEvolution+(form=="mega" ? "":" "+form.replacingOccurrences(of:"mega-",with:"").uppercased())
    }
}

extension L {
    var pokemonMegaCurrentStatsComparison:String {t("현재 능력치 → 메가진화 후 능력치 (현재 레벨·개체값·성격 반영)","Current → Mega stats (current level, IVs and nature)","現在 → メガシンカ後（現在のレベル・個体値・性格を反映）","Actuales → megaevolución (nivel, IV y naturaleza actuales)","Actuelles → Méga (niveau, IV et nature actuels)","Atuais → Mega (nível, IVs e natureza atuais)","Aktuell → Mega (aktuelles Level, DVs und Wesen)","Текущие → Мега (текущий уровень, IV и характер)")}
    var pokemonMegaInfo:String {t("메가진화 정보 보기","View Mega Evolution info","メガシンカ情報を見る","Ver información de megaevolución","Voir les infos Méga-Évolution","Ver informações de Mega Evolução","Mega-Entwicklungsinfos ansehen","Информация о мегаэволюции")}
    var pokemonMegaStatsComparison:String {t("증감은 일반 형태의 기본 능력치와 비교한 값입니다.","Changes are compared with the regular form’s base stats.","増減は通常の姿の種族値との比較です。","Los cambios se comparan con las estadísticas base de la forma normal.","Les écarts sont comparés aux stats de base de la forme normale.","As diferenças são comparadas aos atributos base da forma normal.","Änderungen beziehen sich auf die Basiswerte der normalen Form.","Изменения указаны относительно базовых характеристик обычной формы.")}
}
