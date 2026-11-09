import SwiftUI

@MainActor
struct BattlePartyIndicators: View {
    let status: BattlePartyStatus?
    let expectedCount: Int
    let language: AppLanguage

    private var selected: Int { min(6, max(0, status?.selected ?? expectedCount)) }
    private var fainted: Int { min(selected, max(0, status?.fainted ?? 0)) }
    private var available: Int { selected - fainted }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<6) { index in
                let empty = index >= selected
                let knockedOut = !empty && status != nil && index >= available
                let unknown = !empty && status == nil
                ZStack {
                    Circle().fill(knockedOut || unknown ? Color(white: 0.25) : .white)
                    if !knockedOut && !unknown {
                        Rectangle().fill(.red)
                            .frame(height: 7)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .clipShape(Circle())
                        Rectangle().fill(.black).frame(height: 1.5)
                        Circle().fill(.white).overlay(Circle().strokeBorder(.black, lineWidth: 1)).frame(width: 4, height: 4)
                    }
                    Circle().strokeBorder(.black, lineWidth: 1)
                    if knockedOut || unknown {
                        Image(systemName: knockedOut ? "xmark" : "questionmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 14, height: 14)
                .opacity(empty ? 0.28 : 1)
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
        .help(summary)
    }

    private var summary: String {
        L(language).battlePartySummary(available: available, fainted: fainted, known: status != nil)
    }
}
