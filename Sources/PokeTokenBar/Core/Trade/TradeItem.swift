import Foundation

/// 교환으로 오가는 대상 — 졸업 도감 항목 또는 현재 육성 중인 개체.
enum TradeItem: Codable, Sendable {
    case dexEntry(DexEntry)
    case activeMon(MonState)

    /// 상대에게서 온 값은 신뢰경계 데이터다. `SaveTransfer.sanitized` 와 같은 원칙으로 커밋 직전
    /// 한 번만 정규화한다 — 다운스트림 산술 지점마다 막으면 새 지점이 생길 때마다 재발한다.
    func sanitized() -> TradeItem {
        switch self {
        case .dexEntry(var entry):
            entry.profile?.sanitize()
            return .dexEntry(entry)
        case .activeMon(var mon):
            mon.usedAtStage = min(max(0, mon.usedAtStage), SaveTransfer.maxTokenValue)
            mon.totalForms = min(max(1, mon.totalForms), 12)
            mon.stageIndex = min(max(0, mon.stageIndex), max(0, mon.pathIDs.count - 1))
            mon.profile?.sanitize()
            return .activeMon(mon)
        }
    }

    var rarity: Rarity {
        switch self {
        case .dexEntry(let entry): return entry.rarity
        case .activeMon(let mon): return mon.rarity
        }
    }

    /// 승인 화면이 "무엇을" 주고받는지 밝히기 위한 표시 이름 — 희귀도만으론 되돌릴 수 없는 교환에서
    /// 무엇이 나가는지 알 수 없다. `DexEntry.names` 가 페이로드에 함께 실려오므로 상대 항목의 종 이름도
    /// 네트워크 없이 해석된다. 육성 중 개체는 이름 맵을 싣지 않아 `#id` 로 떨어진다.
    func displayName(language: AppLanguage) -> String {
        switch self {
        case .dexEntry(let entry):
            return entry.names?[entry.finalID].flatMap { language.resolveName($0) } ?? "#\(entry.finalID)"
        case .activeMon(let mon):
            return "#\(mon.currentID)"
        }
    }

    /// 육성 중 개체를 받을 때만 승인 전 경고문구가 필요하다.
    var isActiveMon: Bool {
        if case .activeMon = self { return true }
        return false
    }

    /// 승인 화면·오퍼 피커가 그릴 스프라이트의 종 — 도감 항목은 도감이 보여주는 `finalID`, 육성 중
    /// 개체는 지금 단계의 `currentID`. 화면은 이름과 함께 이 값을 `SpriteView` 에 그대로 넘긴다.
    var displaySpeciesID: Int {
        switch self {
        case .dexEntry(let entry): return entry.finalID
        case .activeMon(let mon): return mon.currentID
        }
    }

    var displayIsShiny: Bool {
        switch self {
        case .dexEntry(let entry): return entry.isShiny
        case .activeMon(let mon): return mon.isShiny
        }
    }

    var displayUnownForm: UnownForm? {
        switch self {
        case .dexEntry(let entry): return entry.unownForm
        case .activeMon(let mon): return mon.unownForm
        }
    }

    /// 이름 조회의 기준 라인 — `PokeProviding.line(baseSpeciesID:)` 는 진화 전 단계를 기준으로 전체
    /// 체인 이름을 돌려준다.
    var displayBaseID: Int {
        switch self {
        case .dexEntry(let entry): return entry.baseID
        case .activeMon(let mon): return mon.baseID
        }
    }
}
