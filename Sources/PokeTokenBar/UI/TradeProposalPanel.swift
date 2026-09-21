import SwiftUI

/// 교환 요약 + 승인/거절. `TradeView`가 `TradeSession.onOffersReady` 콜백에서 만든 스냅샷을
/// 그대로 받는다 — 세션 상태가 그 사이 바뀌어도(withdraw 등) 이 화면은 "그 순간 본 제안"을 고정해 보여준다.
/// 팝오버 안에서는 `.sheet` 대신 교환 탭 본문으로 인라인 표시된다 — transient 팝오버가 닫힐 때 남는
/// 고아 시트가 이후 모든 클릭을 먹는 기존 결함(`PopoverView` 상단 NOTE, `BagView`의 같은 회피) 때문이다.
@MainActor
struct TradeProposalPanel: View {
    let myOffer: TradeItem
    let theirOffer: TradeItem
    let overwriteWarning: String?
    let store: CompanionStore
    let l: L
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l.tradeProposalTitle).font(.headline)
            tradeRow(label: l.tradeGiving, item: myOffer)
            tradeRow(label: l.tradeReceiving, item: theirOffer)
            if let overwriteWarning {
                Text(overwriteWarning)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(l.tradeReject, role: .cancel, action: onReject)
                Spacer()
                Button(l.tradeAccept, action: onAccept)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tradeRow(label: String, item: TradeItem) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            TradeItemRow(item: item, store: store)
            Text(item.rarity.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
        }
    }
}
