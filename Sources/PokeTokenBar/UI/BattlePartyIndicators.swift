import SwiftUI

struct BattlePartyIndicators: View {
    let status: BattlePartyStatus?
    let expectedCount: Int
    let language: AppLanguage

    private var selected: Int { min(6, max(0, status?.selected ?? expectedCount)) }
    private var fainted: Int { min(selected, max(0, status?.fainted ?? 0)) }
    private var available: Int { selected - fainted }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<6) { index in
                let empty = index >= selected
                let knockedOut = !empty && status != nil && index >= available
                let unknown = !empty && status == nil
                ZStack {
                    Circle().fill(knockedOut || unknown ? Color(white: 0.25) : .white)
                    if !knockedOut && !unknown {
                        Rectangle().fill(.red)
                            .frame(height: 7)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .clipShape(Circle())
                        Rectangle().fill(.black).frame(height: 1.5)
                        Circle().fill(.white).overlay(Circle().strokeBorder(.black, lineWidth: 1)).frame(width: 4, height: 4)
                    }
                    Circle().strokeBorder(.black, lineWidth: 1)
                    if knockedOut || unknown {
                        Image(systemName: knockedOut ? "xmark" : "questionmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 14, height: 14)
                .opacity(empty ? 0.28 : 1)
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
        .help(summary)
    }

    private var summary: String {
        let l = L(language)
        guard status != nil else {
            return l.t("상대 출전 상태 확인 불가", "Opponent party status unavailable", "相手の出場状況は不明",
                       "Estado del equipo rival no disponible", "État de l’équipe adverse indisponible",
                       "Estado da equipe adversária indisponível", "Gegnerischer Teamstatus unbekannt", "Статус команды соперника неизвестен")
        }
        return l.t("출전 가능 \(available)마리, 기절 \(fainted)마리", "\(available) available, \(fainted) fainted",
                   "出場可能 \(available)匹、ひんし \(fainted)匹", "\(available) disponibles, \(fainted) debilitados",
                   "\(available) disponibles, \(fainted) K.O.", "\(available) disponíveis, \(fainted) desmaiados",
                   "\(available) kampfbereit, \(fainted) besiegt", "Готовы к бою: \(available), без сознания: \(fainted)")
    }
}
