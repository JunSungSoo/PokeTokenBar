import SwiftUI

@MainActor
struct BattleChoiceSummaryView: View {
    let name: String
    let summary: BattleChoiceSummary
    let selected: Bool
    let mega: Bool
    let language: AppLanguage
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: summary.chosen ? "checkmark.circle.fill" : "circle")
                Text(name).fontWeight(.semibold)
                if mega { Image(systemName: "sparkles").help(L(language).battleMegaEvolution) }
            }
            Text(summary.action).fontWeight(.medium)
            Text(L(language).battleTarget + ": " + summary.target).foregroundStyle(.secondary)
        }
        .font(.caption).lineLimit(1).truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading).frame(height: 54, alignment: .top).padding(8)
        .background(selected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.accentColor : Color.secondary.opacity(0.3)))
        .contentShape(Rectangle())
        .help([name, summary.action, summary.target].joined(separator: " · "))
    }
}
