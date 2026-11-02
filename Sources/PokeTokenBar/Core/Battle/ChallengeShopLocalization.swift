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
        case .statusCure:t("상태이상 회복","Status cure","状態異常回復","Curar estados","Soin du statut","Curar estado","Statusheilung","Лечение статуса")
        case .revive:t("기력의 조각","Revive","げんきのかけら","Revivir","Rappel","Reviver","Beleber","Оживление")
        case .teamHeal30:t("전체 HP 30% 회복","Team HP +30%","全員HP30%回復","Equipo: PS +30%","Équipe : PV +30 %","Equipe: PS +30%","Team: KP +30 %","Команда: ОЗ +30%")
        case .maxRevive:t("기력의 덩어리","Max Revive","げんきのかたまり","Revivir máximo","Rappel Max","Reviver Máximo","Top-Beleber","Полное оживление")
        }
    }
    func challengeShopDescription(_ item:ChallengeShopItem)->String {
        switch item {
        case .fullRecovery:return t("살아 있는 한 마리의 HP·모든 PP·상태이상을 완전히 회복합니다.","Fully restore one living Pokémon's HP, PP and status.","ひんしでない1匹のHP・全PP・状態異常を全回復。","Restaura PS, PP y estados de un Pokémon no debilitado.","Restaure PV, PP et statut d’un Pokémon non K.O.","Restaura PS, PP e estado de um Pokémon consciente.","Heilt KP, AP und Status eines kampffähigen Pokémon.","Восстанавливает ОЗ, ОД и статус одного покемона не в обмороке.")
        case .ppRecovery:return t("살아 있는 한 마리의 모든 기술 PP를 회복합니다.","Restore all move PP of one living Pokémon.","ひんしでない1匹の全技PPを回復。","Restaura todos los PP de un Pokémon no debilitado.","Restaure tous les PP d’un Pokémon non K.O.","Restaura todos os PP de um Pokémon consciente.","Füllt alle AP eines kampffähigen Pokémon auf.","Восстанавливает все ОД одного покемона не в обмороке.")
        case .heal20,.heal40:
            let n=item == .heal20 ? 20:40
            return t("살아 있는 한 마리의 최대 HP \(n)%만큼 회복합니다.","Restore \(n)% maximum HP to one living Pokémon.","ひんしでない1匹の最大HPの\(n)%を回復。","Recupera \(n)% de PS máximos de un Pokémon no debilitado.","Rend \(n) % des PV max d’un Pokémon non K.O.","Restaura \(n)% dos PS máximos de um Pokémon consciente.","Heilt \(n) % der maximalen KP eines kampffähigen Pokémon.","Восстанавливает \(n)% макс. ОЗ одного покемона не в обмороке.")
        case .statusCure:return t("살아 있는 한 마리의 상태이상을 해제합니다. HP·PP는 회복하지 않습니다.","Cure one living Pokémon's status. No HP or PP recovery.","ひんしでない1匹の状態異常を治す。HP・PPは回復しません。","Cura estados de un Pokémon no debilitado. No restaura PS ni PP.","Soigne le statut d’un Pokémon non K.O., sans PV ni PP.","Cura o estado de um Pokémon consciente, sem PS ou PP.","Heilt den Status eines kampffähigen Pokémon, ohne KP oder AP.","Лечит статус одного покемона не в обмороке, без ОЗ и ОД.")
        case .teamHeal30:return t("살아 있는 선발 전원의 HP를 각 최대 HP의 30%만큼 회복합니다. 부활·PP 회복은 없습니다.","Restore 30% maximum HP to every living team member. No revival or PP recovery.","ひんしでない全員の最大HPの30%を回復。復活・PP回復なし。","Recupera 30% de PS máximos de cada miembro no debilitado. Sin revivir ni PP.","Rend 30 % des PV max à chaque membre non K.O. Sans rappel ni PP.","Restaura 30% dos PS máximos de cada membro consciente. Sem reviver ou PP.","Heilt 30 % der maximalen KP aller kampffähigen Teammitglieder. Keine Wiederbelebung oder AP.","Восстанавливает 30% макс. ОЗ всем членам команды не в обмороке. Без оживления и ОД.")
        case .revive,.maxRevive:
            let n=item == .revive ? 50:100
            return t("기절한 한 마리를 최대 HP의 \(n)%로 부활시킵니다. PP는 회복하지 않습니다.","Revive one fainted Pokémon at \(n)% maximum HP. No PP recovery.","ひんしの1匹を最大HPの\(n)%で復活。PP回復なし。","Revive un Pokémon con \(n)% de PS máximos. No restaura PP.","Ranime un Pokémon K.O. avec \(n) % des PV max, sans PP.","Revive um Pokémon com \(n)% dos PS máximos, sem PP.","Belebt ein besiegtes Pokémon mit \(n) % der maximalen KP, ohne AP.","Оживляет одного покемона с \(n)% макс. ОЗ, без ОД.")
        }
    }
}
