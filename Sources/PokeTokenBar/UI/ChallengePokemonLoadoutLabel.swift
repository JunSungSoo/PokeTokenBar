import SwiftUI

/// Individual loadouts distinguish same-species candidates without opening their details.
@MainActor struct ChallengePokemonLoadoutLabel:View {
    let entry:DexEntry
    let language:AppLanguage
    private var nature:String {(entry.nature ?? .hardy).name(language)}
    private var moves:String {(entry.profile?.moves ?? []).map{BattleTextCatalog.shared.moveName($0.name,language:language)}.joined(separator:" / ")}
    var body:some View {
        HStack(alignment:.center,spacing:10) {
            Text(BattleTextCatalog.shared.speciesName(entry.finalID,language:language)).lineLimit(1).fixedSize(horizontal:true,vertical:false)
            VStack(alignment:.leading,spacing:2) {
                Text(nature).font(.caption.weight(.medium))
                Text(moves).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }.frame(maxWidth:.infinity,alignment:.leading)
        }.help("\(L(language).nature): \(nature) · \(moves)")
            .accessibilityIdentifier("challenge-loadout-\(entry.id)")
    }
}
