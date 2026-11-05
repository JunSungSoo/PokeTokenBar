import Foundation

extension L {
    var challengeShop:String {t("챌린지 상점","Challenge shop","チャレンジショップ","Tienda del desafío","Boutique du défi","Loja do desafio","Herausforderungs-Shop","Магазин испытания")}
    var challengeShopHint: String {
        t("시작 시 100포인트 · 승리 보상으로 50포인트 선택 가능 · 구매한 상품은 다음 구매 시 5포인트 인상",
          "Start with 100 points · Choose 50 points as a victory reward · Each purchased product costs 5 more next time",
          "開始時に100ポイント・勝利報酬で50ポイントを選択可能・購入した商品は次回5ポイント値上げ",
          "Empiezas con 100 puntos · Puedes elegir 50 puntos como recompensa · El producto comprado cuesta 5 más la próxima vez",
          "Départ avec 100 points · Récompense de victoire au choix de 50 points · Chaque produit acheté coûte 5 points de plus la prochaine fois",
          "Comece com 100 pontos · Escolha 50 pontos como recompensa de vitória · O produto comprado custa 5 pontos a mais na próxima vez",
          "Start mit 100 Punkten · 50 Punkte als Siegesbelohnung wählbar · Gekaufte Produkte kosten beim nächsten Kauf 5 Punkte mehr",
          "На старте 100 очков · За победу можно выбрать 50 очков · Купленный товар в следующий раз стоит на 5 очков дороже")
    }
    func challengePoints(_ amount:Int)->String {t("\(amount)포인트","\(amount) points","\(amount)ポイント","\(amount) puntos","\(amount) points","\(amount) pontos","\(amount) Punkte","\(amount) очков")}
    var challengeShopTarget:String {t("사용할 포켓몬을 선택하세요","Choose a Pokémon","使うポケモンを選んでください","Elige un Pokémon","Choisis un Pokémon","Escolha um Pokémon","Wähle ein Pokémon","Выберите покемона")}
    func challengeShopBuy(_ price:Int)->String {t("\(price)포인트로 구매·사용","Buy and use · \(price) points","\(price)ポイントで購入・使用","Comprar y usar · \(price) puntos","Acheter et utiliser · \(price) points","Comprar e usar · \(price) pontos","Kaufen und nutzen · \(price) Punkte","Купить и применить · \(price) очков")}
    func challengeShopName(_ item:ChallengeShopItem)->String {
        switch item {
        case .fullRecovery:t("완전 회복","Full recovery","完全回復","Recuperación completa","Récupération complète","Recuperação completa","Vollständige Heilung","Полное восстановление")
        case .ppRecovery:t("PP 전체 회복","Restore all PP","全PP回復","Recuperar todos los PP","Tous les PP","Restaurar todos os PP","Alle AP auffüllen","Все ОД")
        case .ppMoveRecovery:t("PP 선택 기술 회복","Restore selected move PP","選んだ技のPP回復","Recuperar PP de un movimiento","PP d’une capacité","PP de um golpe","AP einer Attacke","ОД выбранного приёма")
        case .heal20:t("HP 20% 회복","Restore 20% HP","HP20%回復","Recuperar 20% de PS","Rendre 20 % des PV","Restaurar 20% dos PS","20 % KP heilen","Восстановить 20% ОЗ")
        case .heal40:t("HP 40% 회복","Restore 40% HP","HP40%回復","Recuperar 40% de PS","Rendre 40 % des PV","Restaurar 40% dos PS","40 % KP heilen","Восстановить 40% ОЗ")
        case .statusCure:t("상태이상 회복","Status cure","状態異常回復","Curar estados","Soin du statut","Curar estado","Statusheilung","Лечение статуса")
        case .revive:t("기력의 조각","Revive","げんきのかけら","Revivir","Rappel","Reviver","Beleber","Оживление")
        case .teamHeal50:t("전체 HP 50% 회복","Team HP +50%","全員HP50%回復","Equipo: PS +50%","Équipe : PV +50 %","Equipe: PS +50%","Team: KP +50 %","Команда: ОЗ +50%")
        case .maxRevive:t("기력의 덩어리","Max Revive","げんきのかたまり","Revivir máximo","Rappel Max","Reviver Máximo","Top-Beleber","Полное оживление")
        }
    }
    func challengeShopDescription(_ item:ChallengeShopItem)->String {
        switch item {
        case .fullRecovery:return t("선발 전원의 HP·모든 기술 PP·상태이상을 완전히 회복하며 기절한 포켓몬도 부활합니다.","Fully restore the whole team's HP, all PP and status, reviving fainted members.","全員のHP・全技PP・状態異常を全回復。ひんしも復活。","Restaura PS, todos los PP y estados de todo el equipo, reviviendo debilitados.","Restaure PV, tous les PP et statut de toute l’équipe, et ranime les K.O.","Restaura PS, todos os PP e estado de toda a equipe, revivendo desmaiados.","Heilt KP, alle AP und Status des gesamten Teams und belebt K.O.-Mitglieder wieder.","Полностью восстанавливает ОЗ, все ОД и статус всей команды и оживляет потерявших сознание.")
        case .ppMoveRecovery:return t("선택한 한 마리의 기술 하나를 골라 PP를 최대치로 회복합니다. 기절 대상도 사용 가능하며 부활시키지는 않습니다.","Fully restore PP of one selected move. Usable on fainted Pokémon without reviving.","選んだ1匹の技1つのPPを全回復。ひんしも対象、復活なし。","Restaura todos los PP de un movimiento elegido, incluso debilitado, sin revivir.","Restaure tous les PP d’une capacité choisie, même K.O., sans ranimer.","Restaura todos os PP de um golpe escolhido, mesmo desmaiado, sem reviver.","Füllt alle AP einer gewählten Attacke auf, auch bei K.O., ohne Wiederbelebung.","Полностью восстанавливает ОД выбранного приёма, даже в обмороке, без оживления.")
        case .ppRecovery:return t("선택한 한 마리의 모든 기술 PP를 회복합니다. 기절한 포켓몬에게도 사용 가능하며 부활시키지는 않습니다.","Restore all move PP, including for a fainted Pokémon. Does not revive.","ひんしを含む1匹の全技PPを回復。復活はしません。","Restaura todos los PP, incluso debilitado. No revive.","Restaure tous les PP, même K.O., sans ranimer.","Restaura todos os PP, mesmo desmaiado. Não revive.","Füllt alle AP auf, auch bei K.O. Keine Wiederbelebung.","Восстанавливает все ОД, в том числе в обмороке. Не оживляет.")
        case .heal20,.heal40:
            let n=item == .heal20 ? 20:40
            return t("선택한 한 마리의 최대 HP \(n)%만큼 회복합니다. 기절 시 부활하며 기존 상태이상도 해제합니다.","Restore \(n)% maximum HP. Revive and cure status if fainted.","1匹の最大HPの\(n)%を回復。ひんしなら復活し状態異常も治す。","Recupera \(n)% de PS máximos. Si está debilitado, revive y cura estados.","Rend \(n) % des PV max. Si K.O., ranime et soigne le statut.","Restaura \(n)% dos PS máximos. Se desmaiado, revive e cura o estado.","Heilt \(n) % der maximalen KP. Bei K.O.: Wiederbelebung und Statusheilung.","Восстанавливает \(n)% макс. ОЗ. При обмороке оживляет и лечит статус.")
        case .statusCure:return t("살아 있고 상태이상이 있는 한 마리의 상태이상을 해제합니다. HP·PP는 회복하지 않습니다.","Cure status on one living, affected Pokémon. No HP or PP recovery.","ひんしでない1匹の状態異常を治す。HP・PPは回復しません。","Cura estados de un Pokémon no debilitado. No restaura PS ni PP.","Soigne le statut d’un Pokémon non K.O., sans PV ni PP.","Cura o estado de um Pokémon consciente, sem PS ou PP.","Heilt den Status eines kampffähigen Pokémon, ohne KP oder AP.","Лечит статус покемона не в обмороке, без ОЗ и ОД.")
        case .teamHeal50:return t("선발 전원의 HP를 각 최대 HP의 50%만큼 회복하며 기절 시 부활·상태이상 해제합니다. 살아 있는 포켓몬의 상태이상과 모든 PP는 유지합니다.","Restore 50% maximum HP to the whole team, reviving and curing fainted members. Living members keep status; PP is unchanged.","全員の最大HPの50%を回復。ひんしは復活し状態回復。生存者の状態と全PPは維持。","Recupera 50% de PS máximos del equipo; revive y cura a los debilitados. Conserva estados de los demás y todos los PP.","Rend 50 % des PV max à l’équipe ; ranime et soigne les K.O. Conserve le statut des autres et les PP.","Restaura 50% dos PS máximos da equipe; revive e cura desmaiados. Mantém estado dos demais e todos os PP.","Heilt 50 % der maximalen Team-KP; belebt K.O.-Mitglieder wieder und heilt deren Status. Sonst bleiben Status und alle AP erhalten.","Восстанавливает 50% макс. ОЗ всей команде, оживляет и лечит потерявших сознание. Сохраняет статус остальных и все ОД.")
        case .revive,.maxRevive:return ""
        }
    }
}
