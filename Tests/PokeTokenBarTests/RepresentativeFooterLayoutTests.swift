import XCTest
import SwiftUI
@testable import PokeTokenBar

/// 도감 하단은 332pt 한 줄에서 종 이름·희귀도·대표 액션을 함께 보여준다. 대표 액션의 번역문을
/// 버튼 본문에 그리면 en/es 에서 그 앞의 종 정보가 잘리므로, 실제 버튼 폭이 로케일과 무관한지 렌더한다.
@MainActor
final class RepresentativeFooterLayoutTests: XCTestCase {
    private func renderedWidth(language: AppLanguage, isRepresentative: Bool) throws -> CGFloat {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "FloatingPetFooter-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: file)
            defaults.removePersistentDomain(forName: suite)
        }
        var state = CompanionState()
        state.language = language
        state.dex = [.init(baseID: 25, finalID: 25, chainOrder: [25], rarity: .common, caughtAt: nil)]
        state.representativeSpeciesID = isRepresentative ? 25 : nil
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(fileURL: file, defaults: defaults)
        let view = FloatingPetAssignmentMenu(store: store, species: try XCTUnwrap(store.dexSpecies.first))
        return NSHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 40)).width
    }

    func testRepresentativeActionStaysIconWidthInEveryLocaleAndState() throws {
        for language in AppLanguage.allCases {
            for isRepresentative in [false, true] {
                let width = try renderedWidth(language: language, isRepresentative: isRepresentative)
                XCTAssertLessThanOrEqual(width, 40,
                                         "\(language) representative=\(isRepresentative) action width \(width)pt")
            }
        }
    }
}
