import SwiftUI

/// The icon slot and two text rows always occupy the same space, selected or otherwise.
@MainActor
struct BattleMoveButtonLabel: View {
    let move: BattleMove
    let language: AppLanguage
    let selected: Bool
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        VStack(alignment:.leading,spacing:4) {
            HStack(spacing:6) {
                Image(systemName:"checkmark.circle.fill").font(.system(size:14,weight:.semibold))
                    .foregroundStyle(Color.accentColor).frame(width:14,height:14)
                    .opacity(selected ? 1 : 0).accessibilityHidden(true)
                Text(BattleTextCatalog.shared.moveName(move.apiName ?? move.name,language:language))
                    .font(.callout.bold()).lineLimit(1)
            }
            Text("\(BattleTextCatalog.shared.typeName(move.type,language:language)) · \(move.pp)/\(move.maxPP) \(L(language).battlePP)")
                .font(.caption2).lineLimit(1).padding(.leading,20)
        }.frame(maxWidth:.infinity,alignment:.leading)
            .padding(.horizontal,10).frame(height:64)
            .background(selected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.07),in:RoundedRectangle(cornerRadius:8))
            .overlay(RoundedRectangle(cornerRadius:8).stroke(selected ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.12),lineWidth:1))
            .opacity(enabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius:8))
    }
}
