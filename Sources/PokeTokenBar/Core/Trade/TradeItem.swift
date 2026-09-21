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

    /// 육성 중 개체를 받을 때만 승인 전 경고문구가 필요하다.
    var isActiveMon: Bool {
        if case .activeMon = self { return true }
        return false
    }
}
