import SwiftUI

struct BattleContentMeasurement: Equatable {
    let content: CGRect
    let commands: CGRect?
    let footer: CGRect?
    let header:CGRect?
    let battlefield:CGRect?
    let battlers:CGRect?
    let roster:CGRect?
    let commandTitle:CGRect?
    var commandClearance: CGFloat? {
        guard let commands, let footer else { return nil }
        return footer.minY - commands.maxY
    }
}

struct BattleContentBoundsKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

extension View {
    func measureBattleContent(_ region: String) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: BattleContentBoundsKey.self,
                value: [region: geometry.frame(in: .named("battle-content"))])
        })
    }
}
