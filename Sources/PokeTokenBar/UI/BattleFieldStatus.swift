import SwiftUI

@MainActor
struct BattleFieldStatus: View {
    let field: BattleFieldState
    let language: AppLanguage
    private var l: L { L(language) }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(l.battleFieldTitle, systemImage: "globe").font(.caption.bold())
            if !field.weather.isEmpty {
                Text(l.battleWeather(field.weather) + timer(field.weatherTiming) + (field.weatherSuppressed ? " · " + l.battleWeatherSuppressed : ""))
            }
            ForEach(field.conditions, id: \.self) { Text(l.battleFieldEffect($0) + timer(field.conditionTimings?[$0])) }
            side(field.ownSide, ally: true)
            side(field.foeSide, ally: false)
        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
            .padding(9).background(Color.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
    }
    @ViewBuilder private func side(_ conditions: [BattleFieldCondition], ally: Bool) -> some View {
        if !conditions.isEmpty {
            Text(l.battleSide(ally: ally) + " · " + conditions.map {
                l.battleFieldEffect($0.id) + ($0.layers > 1 ? " ×\($0.layers)" : "") + timer($0.timing)
            }.joined(separator: " · "))
        }
    }
    private func timer(_ timing: BattleFieldTiming?) -> String {
        " · " + (timing?.label ?? l.battleFieldUntilRemoved)
    }
}
