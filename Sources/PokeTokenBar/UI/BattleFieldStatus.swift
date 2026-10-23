import SwiftUI

@MainActor
struct BattleFieldStatus: View {
    let field: BattleFieldState
    let language: AppLanguage
    private var l: L { L(language) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(l.battleFieldTitle, systemImage: "globe").font(.caption.bold())
            if !field.weather.isEmpty {
                effect(l.battleWeather(field.weather) + timer(field.weatherTiming) + (field.weatherSuppressed ? " · " + l.battleWeatherSuppressed : ""), id:field.weather)
            }
            ForEach(field.conditions, id: \.self) { effect(l.battleFieldEffect($0) + timer(field.conditionTimings?[$0]), id:$0) }
            side(field.ownSide, ally: true)
            side(field.foeSide, ally: false)
        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
            .padding(9).background(Color.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
    }
    @ViewBuilder private func side(_ conditions: [BattleFieldCondition], ally: Bool) -> some View {
        if !conditions.isEmpty {
            ForEach(conditions, id: \.id) { condition in
                effect(l.battleSide(ally: ally) + " · " + l.battleFieldEffect(condition.id)
                    + (condition.layers > 1 ? " ×\(condition.layers)" : "") + timer(condition.timing), id:condition.id)
            }
        }
    }
    private func effect(_ title:String,id:String)->some View {
        VStack(alignment:.leading,spacing:3) {
            Text(title).fontWeight(.semibold)
            if let description=l.battleFieldDescription(id) {
                Text(description).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal:false,vertical:true)
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func timer(_ timing: BattleFieldTiming?) -> String {
        " · " + (timing?.label ?? l.battleFieldUntilRemoved)
    }
}
