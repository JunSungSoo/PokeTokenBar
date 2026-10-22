import SwiftUI

/// Both public six-member rosters fit in two fixed rows; only own choices are marked.
@MainActor
struct BattleTeamPreview: View {
    let own: [BattleRosterMember]
    let opponent: [BattleRosterMember]
    let selected: [String]
    let mode: BattleMode
    let language: AppLanguage
    let enabled: Bool
    let onSelect: (String) -> Void
    private var l: L { L(language) }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(l.battleOwnRoster).font(.caption.bold())
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
                ForEach(own) { member in
                    let position = selected.firstIndex(of: member.id)
                    Button { onSelect(member.id) } label: {
                        card(member, position: position)
                    }.buttonStyle(.plain)
                        .disabled(!enabled || (position == nil && selected.count >= mode.battleSize))
                        .accessibilityIdentifier("battle-preview-own-\(member.id)")
                        .accessibilityLabel(rosterLabel(member))
                        .accessibilityValue(position.map { "\($0 + 1) · " + l.battleSelected } ?? "")
                }
            }
            Text(l.battleOpponentRoster).font(.caption.bold())
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
                ForEach(opponent) { member in
                    opponentCard(member)
                }
                if opponent.isEmpty {
                    ForEach(0..<6, id: \.self) { _ in
                        Image(systemName: "questionmark.circle.fill").font(.title2).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).frame(height: 92)
                    }
                }
            }.accessibilityIdentifier("battle-preview-opponent-roster")
        }
    }
    private func opponentCard(_ member:BattleRosterMember)->some View {
        let focused=own.first{$0.id==selected.last}
        let matchup=focused.map{BattleRosterMatchup.evaluate($0,against:member)}
        let color:Color=matchup?.advantage == .strong ? .green:matchup?.advantage == .weak ? .red:.clear
        return card(member,position:nil)
            .overlay { RoundedRectangle(cornerRadius:6).strokeBorder(color,lineWidth:2) }
            .help(matchup.map{l.battleRosterTypeMatchup($0.outgoing,incoming:$0.incoming)} ?? "")
    }
    private func rosterLabel(_ member:BattleRosterMember)->String {
        let name=BattleTextCatalog.shared.speciesName(member.speciesID,language:language)
        let types=BattleTextCatalog.shared.speciesTypeNames(member.speciesID,form:member.form,language:language)
        return name + ", " + types
    }
    private func card(_ member: BattleRosterMember, position: Int?) -> some View {
        VStack(spacing: 2) {
            SpriteView(speciesID: member.speciesID, size: 38, shiny: member.shiny, form: member.form)
                .padding(.top, 16)
            Text(BattleTextCatalog.shared.speciesName(member.speciesID, language: language))
                .font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.7)
            Text(BattleTextCatalog.shared.speciesTypeNames(member.speciesID, form: member.form, language: language))
                .font(.system(size: 8)).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.6)
                .accessibilityIdentifier("battle-preview-types-\(member.id)")
        }.frame(maxWidth: .infinity).frame(height: 92)
            .background(position == nil ? Color.secondary.opacity(0.08) : Color.accentColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .topLeading) {
                if let position {
                    Text(position == 0 ? "LEAD" : "\(position + 1)")
                        .font(.system(size: 8, weight: .heavy)).padding(3)
                        .foregroundStyle(.white).background(Color.accentColor, in: RoundedRectangle(cornerRadius: 3))
                }
            }
    }
}
