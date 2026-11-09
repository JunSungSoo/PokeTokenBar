import SwiftUI

@MainActor
struct BattleTurnLogView: View {
    let log: BattleTurnLog
    let language: AppLanguage
    let ownPlayer: Int
    @Binding var expanded: Bool
    private var l: L { L(language) }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { expanded.toggle() } label: {
                HStack {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").frame(width:12)
                    Text(l.battleTurnLogTitle).fontWeight(.semibold)
                    Spacer()
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).font(.caption)
                .accessibilityIdentifier("battle-turn-log-toggle")
                .accessibilityValue(l.battleTurnLogState(expanded))
            if expanded {
                let groups=log.groups(language:language,ownPlayer:ownPlayer)
                ScrollView {
                    LazyVStack(alignment:.leading,spacing:8) {
                        if groups.isEmpty { Text(l.battleTurnLogEmpty).foregroundStyle(.secondary) }
                        ForEach(groups.reversed()) { group in
                            VStack(alignment:.leading,spacing:4) {
                                Text(l.battleLogTurn(group.turn)).fontWeight(.semibold).foregroundStyle(.secondary)
                                ForEach(group.entries) { entry in
                                    Text(entry.text).frame(maxWidth:.infinity,alignment:.leading).textSelection(.enabled)
                                }
                            }
                        }
                    }.font(.caption).frame(maxWidth:.infinity,alignment:.leading).padding(4).reservesScrollerLane()
                }.frame(height:120).accessibilityIdentifier("battle-turn-log-entries")
            }
        }.padding(8).background(Color.secondary.opacity(0.06),in:RoundedRectangle(cornerRadius:6))
    }
}
