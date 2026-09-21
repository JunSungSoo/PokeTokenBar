import SwiftUI

/// 교환 항목 한 줄 — 스프라이트 + 이름. 오퍼 피커와 승인 화면(내가 줄 것/받을 것)이 공유한다.
/// 되돌릴 수 없는 교환에서 "무엇을" 주고받는지 이름과 그림 둘 다로 밝힌다(`#37` 만으로는 알 수 없다).
/// 이름은 `store.cachedTradeItemName` 으로 즉시 최선의 값을 보여준 뒤 `resolveTradeItemName` 으로
/// 정확한 값을 채운다 — `CompanionView` 의 캐시-먼저-async-보정 방식을 그대로 따른다.
@MainActor
struct TradeItemRow: View {
    let item: TradeItem
    let store: CompanionStore
    var spriteSize: CGFloat = 28

    @State private var name: String

    init(item: TradeItem, store: CompanionStore, spriteSize: CGFloat = 28) {
        self.item = item
        self.store = store
        self.spriteSize = spriteSize
        _name = State(initialValue: store.cachedTradeItemName(for: item))
    }

    var body: some View {
        HStack(spacing: 6) {
            SpriteView(speciesID: item.displaySpeciesID, size: spriteSize,
                       shiny: item.displayIsShiny, unownForm: item.displayUnownForm)
            Text(name)
        }
        .task {
            name = await store.resolveTradeItemName(for: item)
        }
    }
}
