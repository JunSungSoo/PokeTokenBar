import XCTest
@testable import PokeTokenBar

final class TradeItemTests: XCTestCase {
    private func sampleMon(usedAtStage: Int = 0, totalForms: Int = 2) -> MonState {
        MonState(baseID: 1, pathIDs: [1, 2], stageIndex: 0, usedAtStage: usedAtStage,
                  rarity: .common, totalForms: totalForms)
    }

    private func sampleEntry() -> DexEntry {
        DexEntry(baseID: 1, finalID: 1, chainOrder: [1], rarity: .common, caughtAt: Date())
    }

    func testSanitizedClampsActiveMonUsedAtStageToZeroMinimum() {
        var mon = sampleMon()
        mon.usedAtStage = -5
        guard case .activeMon(let result) = TradeItem.activeMon(mon).sanitized() else {
            return XCTFail("expected activeMon")
        }
        XCTAssertEqual(result.usedAtStage, 0)
    }

    func testSanitizedClampsTotalFormsUpperBound() {
        let mon = sampleMon(totalForms: 999)
        guard case .activeMon(let result) = TradeItem.activeMon(mon).sanitized() else {
            return XCTFail("expected activeMon")
        }
        XCTAssertEqual(result.totalForms, 12)
    }

    func testSanitizedPreservesDexEntryIdentity() {
        let entry = sampleEntry()
        guard case .dexEntry(let result) = TradeItem.dexEntry(entry).sanitized() else {
            return XCTFail("expected dexEntry")
        }
        XCTAssertEqual(result.id, entry.id)
    }

    func testIsActiveMonDistinguishesCases() {
        XCTAssertFalse(TradeItem.dexEntry(sampleEntry()).isActiveMon)
        XCTAssertTrue(TradeItem.activeMon(sampleMon()).isActiveMon)
    }

    func testRarityReadsThroughBothCases() {
        XCTAssertEqual(TradeItem.dexEntry(sampleEntry()).rarity, .common)
        XCTAssertEqual(TradeItem.activeMon(sampleMon()).rarity, .common)
    }
}
