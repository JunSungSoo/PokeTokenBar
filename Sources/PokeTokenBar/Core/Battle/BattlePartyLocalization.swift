import Foundation

extension L {
    func battlePartySummary(available: Int, fainted: Int, known: Bool) -> String {
        guard known else {
            return t("상대 출전 상태 확인 불가", "Opponent party status unavailable", "相手の出場状況は不明",
                       "Estado del equipo rival no disponible", "État de l’équipe adverse indisponible",
                       "Estado da equipe adversária indisponível", "Gegnerischer Teamstatus unbekannt", "Статус команды соперника неизвестен")
        }
        return t("출전 가능 \(available)마리, 기절 \(fainted)마리", "\(available) available, \(fainted) fainted",
                   "出場可能 \(available)匹、ひんし \(fainted)匹", "\(available) disponibles, \(fainted) debilitados",
                   "\(available) disponibles, \(fainted) K.O.", "\(available) disponíveis, \(fainted) desmaiados",
                   "\(available) kampfbereit, \(fainted) besiegt", "Готовы к бою: \(available), без сознания: \(fainted)")
    }
}
