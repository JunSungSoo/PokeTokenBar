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

    /// A profile with an out-of-range IV — `sanitize()` clamps `ivs.hp` to 0...31, so 999 is an
    /// observable witness that `sanitize()` actually ran (as opposed to merely being callable).
    private func profileWithOutOfRangeIV() -> PokemonProfile {
        var profile = PokemonProfile.generate(seed: 1)
        profile.ivs.hp = 999
        return profile
    }

    func testSanitizedClampsActiveMonUsedAtStageToZeroMinimum() {
        var mon = sampleMon()
        mon.usedAtStage = -5
        guard case .activeMon(let result) = TradeItem.activeMon(mon).sanitized() else {
            return XCTFail("expected activeMon")
        }
        XCTAssertEqual(result.usedAtStage, 0)
    }

    func testSanitizedClampsActiveMonUsedAtStageToUpperBound() {
        var mon = sampleMon()
        mon.usedAtStage = SaveTransfer.maxTokenValue + 1
        guard case .activeMon(let result) = TradeItem.activeMon(mon).sanitized() else {
            return XCTFail("expected activeMon")
        }
        XCTAssertEqual(result.usedAtStage, SaveTransfer.maxTokenValue)
    }

    func testSanitizedClampsTotalFormsUpperBound() {
        let mon = sampleMon(totalForms: 999)
        guard case .activeMon(let result) = TradeItem.activeMon(mon).sanitized() else {
            return XCTFail("expected activeMon")
        }
        XCTAssertEqual(result.totalForms, 12)
    }

    func testSanitizedClampsTotalFormsLowerBound() {
        let mon = sampleMon(totalForms: 0)
        guard case .activeMon(let result) = TradeItem.activeMon(mon).sanitized() else {
            return XCTFail("expected activeMon")
        }
        XCTAssertEqual(result.totalForms, 1)
    }

    func testSanitizedClampsStageIndexToZeroMinimum() {
        var mon = sampleMon()
        mon.stageIndex = -5
        guard case .activeMon(let result) = TradeItem.activeMon(mon).sanitized() else {
            return XCTFail("expected activeMon")
        }
        XCTAssertEqual(result.stageIndex, 0)
    }

    func testSanitizedClampsStageIndexToPathIDsUpperBound() {
        var mon = sampleMon()
        mon.stageIndex = 999
        guard case .activeMon(let result) = TradeItem.activeMon(mon).sanitized() else {
            return XCTFail("expected activeMon")
        }
        XCTAssertEqual(result.stageIndex, mon.pathIDs.count - 1)
    }

    func testSanitizedSanitizesActiveMonProfile() {
        var mon = sampleMon()
        mon.profile = profileWithOutOfRangeIV()
        guard case .activeMon(let result) = TradeItem.activeMon(mon).sanitized() else {
            return XCTFail("expected activeMon")
        }
        XCTAssertEqual(result.profile?.ivs.hp, 31)
    }

    func testSanitizedPreservesDexEntryIdentity() {
        let entry = sampleEntry()
        guard case .dexEntry(let result) = TradeItem.dexEntry(entry).sanitized() else {
            return XCTFail("expected dexEntry")
        }
        XCTAssertEqual(result.id, entry.id)
    }

    func testSanitizedSanitizesDexEntryProfile() {
        var entry = sampleEntry()
        entry.profile = profileWithOutOfRangeIV()
        guard case .dexEntry(let result) = TradeItem.dexEntry(entry).sanitized() else {
            return XCTFail("expected dexEntry")
        }
        XCTAssertEqual(result.profile?.ivs.hp, 31)
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
