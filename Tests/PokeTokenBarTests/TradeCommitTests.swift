import XCTest
@testable import PokeTokenBar

private enum TradeCommitStubError: Error { case unavailable }

private struct TradeCommitOfflineProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw TradeCommitStubError.unavailable }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { throw TradeCommitStubError.unavailable }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { throw TradeCommitStubError.unavailable }
}

@MainActor
final class TradeCommitTests: XCTestCase {
    private func fixture() throws -> (CompanionStore, URL) {
        // Own subdirectory per test so a test that removes the state directory
        // (to simulate a backup write failure) never touches the shared temp root.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("trade-commit-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("companion-state.json")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "trade-commit-\(UUID())"))
        let store = CompanionStore(provider: TradeCommitOfflineProvider(), fileURL: url,
                                   dittoDisguiseRollingEnabled: false, defaults: defaults)
        return (store, url)
    }

    func testOverwriteWarningIsNilWhenReceivingDexEntry() throws {
        let (store, _) = try fixture()
        let entry = DexEntry(baseID: 1, finalID: 1, chainOrder: [1], rarity: .common, caughtAt: Date())
        XCTAssertNil(store.tradeOverwriteWarning(forReceiving: .dexEntry(entry)))
    }

    func testOverwriteWarningIsNilWhenIHaveNoActiveMon() throws {
        let (store, _) = try fixture()
        let mon = MonState(baseID: 4, pathIDs: [4], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
        XCTAssertNil(store.tradeOverwriteWarning(forReceiving: .activeMon(mon)))
    }

    func testOverwriteWarningPresentWhenReceivingActiveMonWhileGrowingOne() throws {
        let (store, _) = try fixture()
        store.debugSetActive(MonState(baseID: 1, pathIDs: [1, 2], stageIndex: 0, usedAtStage: 100,
                                      rarity: .common, totalForms: 2))
        let mon = MonState(baseID: 4, pathIDs: [4], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
        XCTAssertNotNil(store.tradeOverwriteWarning(forReceiving: .activeMon(mon)))
    }

    func testApplyTradeCommitCreatesBackupBeforeMutatingState() throws {
        let (store, url) = try fixture()
        let sent = DexEntry(baseID: 1, finalID: 1, chainOrder: [1], rarity: .common, caughtAt: Date())
        store.debugSetDex([sent])
        let received = DexEntry(baseID: 4, finalID: 4, chainOrder: [4], rarity: .common, caughtAt: Date())

        let backupURL = try store.applyTradeCommit(sending: .dexEntry(sent), receiving: .dexEntry(received))

        let dir = url.deletingLastPathComponent()
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix(SaveTransfer.tradeBackupFilePrefix) }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(backupURL.deletingLastPathComponent(), dir)
        XCTAssertFalse(store.state.dex.contains { $0.id == sent.id })
        XCTAssertTrue(store.state.dex.contains { $0.id == received.id })
    }

    func testApplyTradeCommitReplacingActiveMonClearsEggGuarantee() throws {
        let (store, _) = try fixture()
        store.debugSetActive(MonState(baseID: 1, pathIDs: [1], stageIndex: 0, usedAtStage: 0,
                                      rarity: .common, totalForms: 1))
        store.debugSetEggTier(.rare)
        let received = MonState(baseID: 4, pathIDs: [4], stageIndex: 0, usedAtStage: 0,
                                rarity: .common, totalForms: 1)
        let sent = DexEntry(baseID: 1, finalID: 1, chainOrder: [1], rarity: .common, caughtAt: Date())

        try store.applyTradeCommit(sending: .dexEntry(sent), receiving: .activeMon(received))

        XCTAssertEqual(store.state.active?.baseID, 4)
        XCTAssertNil(store.state.eggTier)
    }

    func testApplyTradeCommitAbortsWhenBackupCannotBeWritten() throws {
        let (store, url) = try fixture()
        let dir = url.deletingLastPathComponent()
        let sent = DexEntry(baseID: 1, finalID: 1, chainOrder: [1], rarity: .common, caughtAt: Date())
        store.debugSetDex([sent])
        let received = DexEntry(baseID: 4, finalID: 4, chainOrder: [4], rarity: .common, caughtAt: Date())

        // Replace the state directory with a file so any backup write into it fails.
        try FileManager.default.removeItem(at: dir)
        try Data().write(to: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertThrowsError(try store.applyTradeCommit(sending: .dexEntry(sent), receiving: .dexEntry(received))) { error in
            XCTAssertEqual(error as? SaveTransferError, .backupFailed)
        }
        XCTAssertTrue(store.state.dex.contains { $0.id == sent.id })
        XCTAssertFalse(store.state.dex.contains { $0.id == received.id })
    }
}
