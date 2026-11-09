import SwiftUI

/// Show only current engine stages; numerical stats never enter this presentation model.
struct BattleStatReadout: Identifiable {
    let id: String
    let stage: Int
    var number: String { stage > 0 ? "+\(stage)" : String(stage) }
    var color: Color { stage < 0 ? .blue : stage > 0 ? .red : .primary }
    static func items(_ pokemon: BattleCombatant) -> [Self] {
        ["atk", "def", "spa", "spd", "spe", "accuracy", "evasion"].map {
            Self(id: $0, stage: pokemon.boosts?[$0] ?? 0)
        }
    }
}

@MainActor
struct BattleOwnStats: View {
    let pokemon: BattleCombatant
    let language: AppLanguage
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(BattleTextCatalog.shared.speciesName(pokemon.speciesID, language: language))
                .font(.caption.weight(.semibold))
            if let ability = pokemon.ability {
                Label(BattleTextCatalog.shared.abilityName(ability, language: language), systemImage: "sparkles")
                    .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("battle-active-ability")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 8)], alignment: .leading, spacing: 6) {
                ForEach(BattleStatReadout.items(pokemon)) { item in
                    HStack(spacing: 0) {
                        Text("(" + L(language).battleStat(item.id) + " : ").foregroundStyle(.secondary)
                        Text(item.number).foregroundStyle(item.color).monospacedDigit()
                        Text(")").foregroundStyle(.secondary)
                    }.font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                }
            }
            heldItemDetails
            ForEach(pokemon.effects ?? [], id: \.self) { effect in
                Label(L(language).battleActiveEffect(effect), systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var heldItemDetails: some View {
        let l = L(language)
        let item = BattleHeldItems.item(pokemon.item)
        return VStack(alignment: .leading, spacing: 3) {
            Text(l.battleHeldItem + ": " + (item?.name(language) ?? l.battleNoItem))
                .font(.caption.weight(.semibold))
            if let item, let description = item.descriptions[language.rawValue] {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }
}
