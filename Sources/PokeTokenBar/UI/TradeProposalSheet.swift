import SwiftUI

/// 교환 요약 + 승인/거절. `TradeView`가 `TradeSession.onOffersReady` 콜백에서 만든 스냅샷을
/// 그대로 받는다 — 세션 상태가 그 사이 바뀌어도(withdraw 등) 이 화면은 "그 순간 본 제안"을 고정해 보여준다.
@MainActor
struct TradeProposalSheet: View {
    let myOffer: TradeItem
    let theirOffer: TradeItem
    let overwriteWarning: String?
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
        .padding(PopoverMetrics.padding)
        .frame(width: PopoverMetrics.width)
    }

    private func tradeRow(label: String, item: TradeItem) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(item.rarity.rawValue.capitalized)
        }
    }
}
