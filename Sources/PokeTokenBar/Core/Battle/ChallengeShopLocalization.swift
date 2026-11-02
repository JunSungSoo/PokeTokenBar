import Foundation

extension L {
    var challengeShop:String {t("챌린지 상점","Challenge shop","チャレンジショップ","Tienda del desafío","Boutique du défi","Loja do desafio","Herausforderungs-Shop","Магазин испытания")}
    var challengeShopHint:String {t("승리마다 100포인트 · 구매는 선택사항이며 잔액 내에서 반복 구매할 수 있습니다.","100 points per win · Optional purchases, repeat while points last.","勝利ごとに100ポイント・購入は任意、残高内で何度でも購入できます。","100 puntos por victoria · Compra opcional y repetible con saldo.","100 points par victoire · Achats facultatifs, renouvelables selon le solde.","100 pontos por vitória · Compras opcionais e repetíveis com saldo.","100 Punkte pro Sieg · Optionale Käufe, solange Punkte reichen.","100 очков за победу · Покупки необязательны и доступны по балансу.")}
    func challengePoints(_ amount:Int)->String {t("\(amount)포인트","\(amount) points","\(amount)ポイント","\(amount) puntos","\(amount) points","\(amount) pontos","\(amount) Punkte","\(amount) очков")}
    var challengeShopTarget:String {t("사용할 포켓몬을 선택하세요","Choose a Pokémon","使うポケモンを選んでください","Elige un Pokémon","Choisis un Pokémon","Escolha um Pokémon","Wähle ein Pokémon","Выберите покемона")}
    func challengeShopBuy(_ price:Int)->String {t("\(price)포인트로 구매·사용","Buy and use · \(price) points","\(price)ポイントで購入・使用","Comprar y usar · \(price) puntos","Acheter et utiliser · \(price) points","Comprar e usar · \(price) pontos","Kaufen und nutzen · \(price) Punkte","Купить и применить · \(price) очков")}
    func challengeShopName(_ item:ChallengeShopItem)->String {
        switch item {
        case .fullRecovery:t("완전 회복","Full recovery","完全回復","Recuperación completa","Récupération complète","Recuperação completa","Vollständige Heilung","Полное восстановление")
        case .ppRecovery:t("PP 전체 회복","Restore all PP","全PP回復","Recuperar todos los PP","Tous les PP","Restaurar todos os PP","Alle AP auffüllen","Все ОД")
        case .heal20:t("HP 20% 회복","Restore 20% HP","HP20%回復","Recuperar 20% de PS","Rendre 20 % des PV","Restaurar 20% dos PS","20 % KP heilen","Восстановить 20% ОЗ")
        case .heal40:t("HP 40% 회복","Restore 40% HP","HP40%回復","Recuperar 40% de PS","Rendre 40 % des PV","Restaurar 40% dos PS","40 % KP heilen","Восстановить 40% ОЗ")
        }
    }
    func challengeShopDescription(_ item:ChallengeShopItem)->String {
        switch item {
        case .fullRecovery:return t("선택한 한 마리의 HP·모든 기술 PP·상태이상을 모두 회복하며, 기절했다면 부활합니다.","Fully restore one Pokémon's HP and all PP, cure status and revive if fainted.","選んだ1匹のHP・全技PP・状態異常を全回復し、ひんしなら復活します。","Restaura PS y todos los PP de un Pokémon, cura estados y revive.","Restaure les PV et tous les PP d’un Pokémon, soigne son statut et le ranime.","Restaura PS e todos os PP, cura o estado e revive um Pokémon.","Heilt KP und alle AP eines Pokémon, beseitigt Status und belebt wieder.","Полностью восстанавливает ОЗ и ОД одного покемона, лечит статус и оживляет.")
        case .ppRecovery:return t("선택한 한 마리의 장착한 모든 기술 PP를 최대치로 회복합니다.","Restore all equipped move PP of one Pokémon to maximum.","選んだ1匹が覚えている全技のPPを全回復します。","Restaura todos los PP de los movimientos de un Pokémon.","Restaure tous les PP des capacités d’un Pokémon.","Restaura todos os PP dos golpes de um Pokémon.","Füllt alle AP der ausgerüsteten Attacken eines Pokémon auf.","Восстанавливает все ОД всех выбранных приёмов одного покемона.")
        case .heal20,.heal40:
            let percent=item == .heal20 ? 20:40
            return t("선택한 한 마리의 최대 HP \(percent)%만큼 회복합니다. 기절했다면 부활합니다.","Restore \(percent)% of one Pokémon's maximum HP. Revives if fainted.","選んだ1匹の最大HPの\(percent)%を回復。ひんしなら復活します。","Recupera el \(percent)% de los PS máximos de un Pokémon. Revive si está debilitado.","Rend \(percent) % des PV maximum d’un Pokémon. Le ranime si K.O.","Restaura \(percent)% dos PS máximos de um Pokémon. Revive se desmaiado.","Heilt \(percent) % der maximalen KP eines Pokémon, auch bei K.O.","Восстанавливает \(percent)% максимальных ОЗ одного покемона. Оживляет.")
        }
    }
}
